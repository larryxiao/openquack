import Foundation
import OpenQuackKit

/// Categorical classification of what went wrong when a transcript is incorrect.
/// Applied per clip in priority order; `.ok` means the output passed all checks.
public enum FailureMode: String, Sendable {
    /// Bracket annotation from training data leaked into output, e.g. "[SPEAKING CHINESE]".
    case placeholder
    /// Audio is CJK-script but output is Latin — Whisper produced a translation instead of a transcript.
    case silentTranslation
    /// WER exceeds 200 % — output is longer or more garbled than the reference.
    case garbled
    /// Output is plausibly correct.
    case ok
}

public struct ClipMetrics {
    public let clipID: String
    public let audioSeconds: Double
    public let wallSeconds: Double
    public let wer: Double
    public let cer: Double
    public let ttft: Double?
    public let detectedLanguage: String?
    public let textPreview: String
    public let failureMode: FailureMode
    public let outputScriptMatch: Bool
    public let hallucRateRaw: Double
}

public struct BenchResult {
    public let engineName: String
    public let modelID: String
    public let coldStartSeconds: Double
    public let peakRSSBytes: Int64
    public let perClip: [ClipMetrics]
    public let error: String?

    public var meanWER: Double { mean(perClip.map(\.wer)) }
    public var meanCER: Double { mean(perClip.map(\.cer)) }
    public var meanRTF: Double {
        let rtfs = perClip.compactMap { c -> Double? in
            c.audioSeconds > 0 ? c.wallSeconds / c.audioSeconds : nil
        }
        return mean(rtfs)
    }
    public var meanWallSeconds: Double { mean(perClip.map(\.wallSeconds)) }

    public var failureCounts: (ok: Int, placeholder: Int, silentTranslation: Int, garbled: Int) {
        var ok = 0, ph = 0, st = 0, ga = 0
        for c in perClip {
            switch c.failureMode {
            case .ok:                ok += 1
            case .placeholder:       ph += 1
            case .silentTranslation: st += 1
            case .garbled:           ga += 1
            }
        }
        return (ok, ph, st, ga)
    }
}

private func mean(_ xs: [Double]) -> Double {
    xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
}

public enum BenchRunner {
    public static func run(
        engineKind: EngineKind,
        model: String,
        clips: [Clip],
        language: String?,
        verbose: Bool
    ) async -> BenchResult {
        stderr("◇ \(engineKind.rawValue) / \(model): loading...")

        let engine: any TranscriptionEngine
        let coldStart: TimeInterval
        do {
            (engine, coldStart) = try await engineKind.makeEngine(model: model)
        } catch {
            stderr("  ✗ load failed: \(error)")
            return BenchResult(
                engineName: engineKind.rawValue,
                modelID: model,
                coldStartSeconds: 0,
                peakRSSBytes: 0,
                perClip: [],
                error: "load failed: \(error)"
            )
        }
        stderr("  ✓ loaded in \(fmt(coldStart, 2))s")

        let sampler = RSSSampler(intervalMs: 100)
        sampler.start()

        var perClip: [ClipMetrics] = []
        for (i, clip) in clips.enumerated() {
            do {
                let r = try await engine.transcribe(audioFile: clip.url, language: language)
                let wer = WER.compute(reference: clip.reference, hypothesis: r.text)
                let cer = WER.cer(reference: clip.reference, hypothesis: r.text)
                let preview = String(r.text.prefix(80))
                let mode = classifyFailureMode(reference: clip.reference, hypothesis: r.text, wer: wer)
                let scriptMatch = outputScriptMatch(reference: clip.reference, hypothesis: r.text)
                let halluc = hallucRateRaw(hypothesis: r.text)
                perClip.append(ClipMetrics(
                    clipID: clip.id,
                    audioSeconds: r.audioSeconds,
                    wallSeconds: r.wallSeconds,
                    wer: wer,
                    cer: cer,
                    ttft: r.timeToFirstToken,
                    detectedLanguage: r.detectedLanguage,
                    textPreview: preview,
                    failureMode: mode,
                    outputScriptMatch: scriptMatch,
                    hallucRateRaw: halluc
                ))
                if verbose {
                    let rtf = r.audioSeconds > 0 ? r.wallSeconds / r.audioSeconds : 0
                    let modeStr = mode == .ok ? "ok" : "!\(mode.rawValue)"
                    stderr("  [\(i+1)/\(clips.count)] \(clip.id): WER=\(fmt(wer, 3)) RTF=\(fmt(rtf, 2))× [\(modeStr)]")
                }
            } catch {
                stderr("  [\(i+1)/\(clips.count)] \(clip.id): ERROR \(error)")
            }
        }

        let peakRSS = sampler.stop()
        return BenchResult(
            engineName: engineKind.rawValue,
            modelID: model,
            coldStartSeconds: coldStart,
            peakRSSBytes: peakRSS,
            perClip: perClip,
            error: perClip.isEmpty ? "no successful clips" : nil
        )
    }
}

private func fmt(_ x: Double, _ frac: Int) -> String {
    String(format: "%.\(frac)f", x)
}

func stderr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8) ?? Data())
}

// ── Failure-mode classification ───────────────────────────────────────────

/// Bracket-annotation patterns that leak from Whisper's pretraining data.
private let placeholderRE = try! NSRegularExpression(
    pattern: #"\[(SPEAKING|FOREIGN|INAUDIBLE|MUSIC|NOISE|APPLAUSE)[^\]]*\]"#,
    options: .caseInsensitive
)

func classifyFailureMode(reference: String, hypothesis: String, wer: Double) -> FailureMode {
    let hyp = hypothesis.trimmingCharacters(in: .whitespacesAndNewlines)
    // 1. Bracket hallucination (highest priority — catches "[SPEAKING CHINESE]" etc.)
    if !hyp.isEmpty {
        let range = NSRange(hyp.startIndex..., in: hyp)
        if placeholderRE.firstMatch(in: hyp, range: range) != nil {
            return .placeholder
        }
    }
    // 2. Silent translation: CJK reference but Latin-dominant output.
    if cjkFraction(reference) > 0.30 && latinAlphaFraction(hyp) > 0.70 {
        return .silentTranslation
    }
    // 3. Garbled: more than twice as many tokens as reference (WER > 200 %).
    if wer > 2.0 {
        return .garbled
    }
    return .ok
}

/// True when both reference and hypothesis share the same dominant script
/// (both CJK or both non-CJK). Catches cross-script failures independently
/// of the WER value.
func outputScriptMatch(reference: String, hypothesis: String) -> Bool {
    let refIsCJK = cjkFraction(reference) > 0.30
    let hypIsCJK = cjkFraction(hypothesis) > 0.10
    return refIsCJK == hypIsCJK
}

/// Fraction of output characters that are bracket annotations: [.*?].
func hallucRateRaw(hypothesis: String) -> Double {
    guard !hypothesis.isEmpty else { return 0 }
    let re = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)
    let range = NSRange(hypothesis.startIndex..., in: hypothesis)
    let matches = re.matches(in: hypothesis, range: range)
    let bracketed = matches.reduce(0) { $0 + $1.range.length }
    return Double(bracketed) / Double(hypothesis.utf16.count)
}

// ── Unicode script helpers ────────────────────────────────────────────────

private func cjkFraction(_ s: String) -> Double {
    let scalars = s.unicodeScalars
    guard !scalars.isEmpty else { return 0 }
    let cjkCount = scalars.filter { isCJKScalar($0) }.count
    return Double(cjkCount) / Double(scalars.count)
}

/// Fraction of alphabetic characters in s that fall in the Latin script block.
/// Uses alphabetic characters as denominator to ignore digits, spaces, punctuation.
private func latinAlphaFraction(_ s: String) -> Double {
    let alphas = s.unicodeScalars.filter { $0.properties.isAlphabetic }
    guard !alphas.isEmpty else { return 0 }
    // Basic Latin (0–0x024F covers Latin Extended-B, well past any CJK overlap).
    let latin = alphas.filter { $0.value <= 0x024F }.count
    return Double(latin) / Double(alphas.count)
}

private func isCJKScalar(_ s: Unicode.Scalar) -> Bool {
    let v = s.value
    return (v >= 0x4E00 && v <= 0x9FFF)   // CJK Unified Ideographs
        || (v >= 0x3400 && v <= 0x4DBF)   // CJK Extension A
        || (v >= 0xF900 && v <= 0xFAFF)   // CJK Compatibility Ideographs
        || (v >= 0xAC00 && v <= 0xD7AF)   // Hangul syllables
        || (v >= 0x3040 && v <= 0x309F)   // Hiragana
        || (v >= 0x30A0 && v <= 0x30FF)   // Katakana
}
