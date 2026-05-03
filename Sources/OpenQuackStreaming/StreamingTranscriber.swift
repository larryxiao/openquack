import Foundation
import WhisperKit

/// SPEC-012: streaming transcription that chunks audio at silence boundaries
/// while recording is still in flight, so post-stop wait is bounded by
/// `maxChunkSeconds * RTF` instead of growing with utterance length.
///
/// Owned by the bench harness today; re-homes into `OpenQuackKit/Streaming/`
/// when the AppDelegate wiring lands. Public surface is the one in
/// `docs/SPECS/SPEC-012-streaming-transcription.md`.
public actor StreamingTranscriber {
    public struct Config: Sendable {
        /// Below this many seconds the caller should bypass streaming and
        /// transcribe offline; the actor still works for shorter clips, but
        /// for the M4/16GB / WhisperKit-medium baseline the offline path is
        /// faster end-to-end on short audio.
        public var streamingThreshold: TimeInterval
        /// Cuts happen at the next silence past this mark, never before.
        public var targetChunkSeconds: TimeInterval
        /// If no silence is found by this point, force-cut anyway.
        public var maxChunkSeconds: TimeInterval
        /// Energy threshold passed through to `EnergyVAD`.
        public var silenceEnergyThreshold: Float
        /// Cap on chunks transcribing at once. Default 1: bumping it gives
        /// headroom against RTF spikes at the cost of double peak RAM.
        public var maxInFlightChunks: Int

        public init(
            streamingThreshold: TimeInterval = 30,
            targetChunkSeconds: TimeInterval = 20,
            maxChunkSeconds: TimeInterval = 28,
            silenceEnergyThreshold: Float = 0.02,
            maxInFlightChunks: Int = 1
        ) {
            self.streamingThreshold = streamingThreshold
            self.targetChunkSeconds = targetChunkSeconds
            self.maxChunkSeconds = maxChunkSeconds
            self.silenceEnergyThreshold = silenceEnergyThreshold
            self.maxInFlightChunks = maxInFlightChunks
        }
    }

    public struct Result: Sendable {
        public let text: String
        public let detectedLanguage: String?
        public let audioSeconds: Double
        public let wallSeconds: Double
        public let chunkCount: Int
        public let chunkFailures: Int
    }

    private let pipe: WhisperKit
    private let config: Config
    private let vad: EnergyVAD
    private let sampleRate: Int = 16000

    private var buffer: [Float] = []
    private var bufferStartSample: Int = 0
    private var beginTime: Date?
    private var language: String?
    private var promptTokens: [Int]?
    private var ended: Bool = false
    private var cancelled: Bool = false

    private struct ChunkOutcome: Sendable {
        let text: String
        let detectedLanguage: String?
        let succeeded: Bool
    }

    /// Outcomes keyed by their starting sample (global, monotonic) so the
    /// caller can re-order on `finish()`.
    private var chunkOutcomes: [Int: ChunkOutcome] = [:]
    private var queue: [(start: Int, samples: [Float])] = []
    private var drainTask: Task<Void, Never>?

    public init(pipe: WhisperKit, config: Config = .init()) {
        self.pipe = pipe
        self.config = config
        self.vad = EnergyVAD(
            sampleRate: 16000,
            frameLength: 0.1,
            frameOverlap: 0,
            energyThreshold: config.silenceEnergyThreshold
        )
    }

    public func begin(language: String?, customWords: String?) {
        buffer.removeAll(keepingCapacity: true)
        bufferStartSample = 0
        chunkOutcomes.removeAll()
        queue.removeAll()
        drainTask?.cancel()
        drainTask = nil
        ended = false
        cancelled = false
        beginTime = Date()
        self.language = language
        self.promptTokens = encodePrompt(customWords: customWords)
    }

    public func appendFrames(_ samples: [Float], sampleRate inputRate: Double) {
        guard !cancelled, !ended else { return }
        let resampled = resampleIfNeeded(samples, from: inputRate)
        buffer.append(contentsOf: resampled)
        emitChunksIfReady()
    }

    public func finish() async throws -> Result {
        ended = true
        // Submit whatever's left as the tail.
        if !buffer.isEmpty {
            let tail = buffer
            buffer.removeAll(keepingCapacity: true)
            let start = bufferStartSample
            bufferStartSample += tail.count
            queue.append((start: start, samples: tail))
            startDrainIfNeeded()
        }
        // Wait for the queue to fully drain.
        await drainTask?.value

        let ordered = chunkOutcomes.keys.sorted().compactMap { chunkOutcomes[$0] }
        let texts = ordered.map(\.text).filter { !$0.isEmpty }
        let text = stitchChunks(texts).trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = ordered.compactMap(\.detectedLanguage).first
        let failures = ordered.filter { !$0.succeeded }.count

        let audioSecs = Double(bufferStartSample) / Double(sampleRate)
        let wall = beginTime.map { Date().timeIntervalSince($0) } ?? 0

        return Result(
            text: text,
            detectedLanguage: lang,
            audioSeconds: audioSecs,
            wallSeconds: wall,
            chunkCount: ordered.count,
            chunkFailures: failures
        )
    }

    public func cancel() {
        cancelled = true
        ended = true
        drainTask?.cancel()
        drainTask = nil
        queue.removeAll()
        buffer.removeAll(keepingCapacity: false)
        chunkOutcomes.removeAll()
        beginTime = nil
    }

    // MARK: - cut-point logic

    private func emitChunksIfReady() {
        let target = Int(config.targetChunkSeconds) * sampleRate
        let max_   = Int(config.maxChunkSeconds)    * sampleRate
        // While we have at least targetSeconds buffered, decide whether to
        // cut. If we have ≥ max, we cut at the next silence inside [target,
        // max] — or force-cut at max if no silence was found.
        while buffer.count >= target {
            let windowEnd = min(buffer.count, max_)
            let cutSample: Int
            if let cut = findCutPoint(start: target, end: windowEnd) {
                cutSample = cut
            } else if buffer.count >= max_ {
                cutSample = max_
            } else {
                break  // wait for more frames; silence may yet appear
            }

            let chunk = Array(buffer.prefix(cutSample))
            buffer.removeFirst(cutSample)
            let start = bufferStartSample
            bufferStartSample += cutSample
            queue.append((start: start, samples: chunk))
            startDrainIfNeeded()
        }
    }

    /// Mirrors `VADAudioChunker.splitOnMiddleOfLongestSilence`: search the
    /// second half of `[start, end)` for the longest silence, return the
    /// audio-sample index of its midpoint. Nil when no silence found.
    private func findCutPoint(start: Int, end: Int) -> Int? {
        guard end > start, end <= buffer.count else { return nil }
        let mid = start + (end - start) / 2
        guard mid < end else { return nil }
        let slice = Array(buffer[mid..<end])
        let voice = vad.voiceActivity(in: slice)
        guard let silence = vad.findLongestSilence(in: voice) else { return nil }
        let silenceMidVAD = silence.startIndex + (silence.endIndex - silence.startIndex) / 2
        return mid + vad.voiceActivityIndexToAudioSampleIndex(silenceMidVAD)
    }

    // MARK: - drain queue (bounded by maxInFlightChunks)

    private func startDrainIfNeeded() {
        guard drainTask == nil, !cancelled else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            if cancelled { break }
            // For maxInFlightChunks=1 we just transcribe one at a time.
            // (Bumping to N would batch N at a time; deferred until the
            // RAM/RTF trade-off is benched per SPEC-012.)
            let next = queue.removeFirst()
            let outcome = await transcribeOne(samples: next.samples)
            // cancel() may have raced while we awaited transcribeOne; if so
            // discard the result so the post-cancel state stays clean.
            if cancelled { break }
            chunkOutcomes[next.start] = outcome
        }
        drainTask = nil
    }

    private func transcribeOne(samples: [Float]) async -> ChunkOutcome {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language
        options.verbose = false
        options.withoutTimestamps = true
        if let p = promptTokens, !p.isEmpty {
            options.promptTokens = p
        }
        do {
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return ChunkOutcome(text: text, detectedLanguage: results.first?.language, succeeded: true)
        } catch {
            return ChunkOutcome(text: "", detectedLanguage: nil, succeeded: false)
        }
    }

    // MARK: - chunk stitching

    /// Whisper occasionally re-emits the boundary word when a chunk starts
    /// mid-utterance. Per SPEC-012 §Stop semantics step 4 we drop a single
    /// trailing/leading duplicate at each chunk seam. Comparison normalises
    /// case and strips trailing punctuation; keeps the longer-cased form.
    private func stitchChunks(_ chunks: [String]) -> String {
        guard let first = chunks.first else { return "" }
        var out = first
        for next in chunks.dropFirst() {
            let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nextTrimmed.isEmpty else { continue }

            let lastWord = lastWord(of: out)
            let nextWords = nextTrimmed.split(whereSeparator: { $0.isWhitespace })
            let firstWord = nextWords.first.map(String.init) ?? ""

            if !lastWord.isEmpty,
               wordKey(lastWord) == wordKey(firstWord) {
                let stripped = nextWords.dropFirst().joined(separator: " ")
                if !stripped.isEmpty { out += " " + stripped }
            } else {
                out += " " + nextTrimmed
            }
        }
        return out
    }

    private func lastWord(of s: String) -> String {
        let parts = s.split(whereSeparator: { $0.isWhitespace })
        return parts.last.map(String.init) ?? ""
    }

    private func wordKey(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    // MARK: - prompt + resampling

    private func encodePrompt(customWords: String?) -> [Int]? {
        guard let words = customWords?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty else {
            return nil
        }
        let joined = words
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !joined.isEmpty, let tok = pipe.tokenizer else { return nil }
        return tok.encode(text: " " + joined)
    }

    private func resampleIfNeeded(_ samples: [Float], from inputRate: Double) -> [Float] {
        let inRate = Int(inputRate.rounded())
        if inRate == sampleRate || inRate == 0 { return samples }
        // Simple linear-interpolation resampler. Good enough for VAD/Whisper
        // (which downsample further internally). For the bench we feed 16 kHz
        // direct, so this path is exercised only when wired to AudioRecorder
        // in AppDelegate at 44.1/48 kHz.
        let inCount = samples.count
        guard inCount > 1 else { return samples }
        let ratio = Double(sampleRate) / Double(inRate)
        let outCount = Int(Double(inCount) * ratio)
        var out = [Float](repeating: 0, count: outCount)
        let step = 1.0 / ratio
        for i in 0..<outCount {
            let pos = Double(i) * step
            let i0 = Int(pos)
            let i1 = min(i0 + 1, inCount - 1)
            let t = Float(pos - Double(i0))
            out[i] = samples[i0] * (1 - t) + samples[i1] * t
        }
        return out
    }
}
