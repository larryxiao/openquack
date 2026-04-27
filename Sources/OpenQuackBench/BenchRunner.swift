import Foundation
import OpenQuackKit

public struct ClipMetrics {
    public let clipID: String
    public let audioSeconds: Double
    public let wallSeconds: Double
    public let wer: Double
    public let cer: Double
    public let ttft: Double?
    public let detectedLanguage: String?
    public let textPreview: String   // first ~80 chars, for eyeballing
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
                perClip.append(ClipMetrics(
                    clipID: clip.id,
                    audioSeconds: r.audioSeconds,
                    wallSeconds: r.wallSeconds,
                    wer: wer,
                    cer: cer,
                    ttft: r.timeToFirstToken,
                    detectedLanguage: r.detectedLanguage,
                    textPreview: preview
                ))
                if verbose {
                    let rtf = r.audioSeconds > 0 ? r.wallSeconds / r.audioSeconds : 0
                    stderr("  [\(i+1)/\(clips.count)] \(clip.id): WER=\(fmt(wer, 3)) RTF=\(fmt(rtf, 2))×")
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
