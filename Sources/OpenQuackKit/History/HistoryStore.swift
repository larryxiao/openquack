import Foundation
import AVFoundation
import CoreMedia

/// SPEC-014 — Local audio + transcript history.
///
/// On-disk store of recent dictations. One directory per recording under
/// `~/Library/Application Support/OpenQuack/History/`. Transcripts are
/// plaintext; audio (when enabled) is Opus on macOS 14+, AAC on macOS 13.
/// Retention bounded by count + age + size; eviction is oldest-first.
///
/// All access is serialised through the actor; disk IO inside actor methods
/// is synchronous Foundation IO except the audio encode, which drives an
/// `AVAssetWriter` to completion before returning.

public enum HistoryError: Error, CustomStringConvertible {
    case writeFailed(String)
    case readFailed(String)
    case encodingFailed(String)
    case notFound(UUID)

    public var description: String {
        switch self {
        case .writeFailed(let m):    return "History write failed: \(m)"
        case .readFailed(let m):     return "History read failed: \(m)"
        case .encodingFailed(let m): return "History audio encode failed: \(m)"
        case .notFound(let id):      return "History entry not found: \(id)"
        }
    }
}

public struct HistoryEntry: Sendable, Identifiable, Codable {
    public let id: UUID
    public let recordedAt: Date
    public let transcribedAt: Date?
    public let durationSeconds: TimeInterval
    public let transcript: String?
    public let language: String?
    public let modelID: String?
    /// Nil when audio history is off or the recording is transcript-only.
    public let audioURL: URL?

    public init(id: UUID,
                recordedAt: Date,
                transcribedAt: Date?,
                durationSeconds: TimeInterval,
                transcript: String?,
                language: String?,
                modelID: String?,
                audioURL: URL?) {
        self.id = id
        self.recordedAt = recordedAt
        self.transcribedAt = transcribedAt
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.language = language
        self.modelID = modelID
        self.audioURL = audioURL
    }
}

public struct RetentionPolicy: Sendable {
    public var maxEntries: Int           // default 50
    public var maxAge: TimeInterval      // default 14 days
    public var maxBytesOnDisk: Int64     // default 500 MB

    public init(maxEntries: Int = 50,
                maxAge: TimeInterval = 14 * 24 * 60 * 60,
                maxBytesOnDisk: Int64 = 500 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxAge = maxAge
        self.maxBytesOnDisk = maxBytesOnDisk
    }

    public static let `default` = RetentionPolicy()

    /// The user-facing policy: the entry count is the only lever the user sets;
    /// age/disk caps stay loose. Built here so app launch and the Settings
    /// picker share one definition — otherwise the saved cap silently reverts
    /// to `.default` (50) on every launch until Settings → History is opened.
    public static func userConfigured(maxEntries: Int) -> RetentionPolicy {
        RetentionPolicy(
            maxEntries: maxEntries,
            maxAge: 365 * 24 * 60 * 60,
            maxBytesOnDisk: 5 * 1024 * 1024 * 1024
        )
    }
}

/// On-disk JSON shape. Versioned so future schema changes can migrate.
private struct HistoryMeta: Codable {
    var schemaVersion: Int = 1
    var id: UUID
    var recordedAt: Date
    var transcribedAt: Date?
    var durationSeconds: TimeInterval
    var language: String?
    var modelID: String?
    /// Codec label for the audio file ("opus" | "aac"). Nil iff transcript-only.
    var audioFormat: String?
    /// Filename inside the entry directory (e.g. "audio.caf" / "audio.m4a").
    var audioFilename: String?
}

public actor HistoryStore {
    private let rootURL: URL
    private var policy: RetentionPolicy

    /// Default root: `~/Library/Application Support/OpenQuack/History`.
    public static var defaultRootURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("OpenQuack/History", isDirectory: true)
    }

    public init(rootURL: URL = HistoryStore.defaultRootURL,
                policy: RetentionPolicy = .default) {
        self.rootURL = rootURL
        self.policy = policy
    }

    public func setPolicy(_ newPolicy: RetentionPolicy) {
        self.policy = newPolicy
    }

    // MARK: - Save

    /// Persist a completed (or in-progress) dictation. Pass `audio: nil` for
    /// transcript-only history; pass `audio:` non-nil with `transcript: ""`
    /// for the recovery flow (audio first, transcript filled in later via
    /// `markTranscribed`).
    ///
    /// The `audioSampleRate` parameter extends SPEC-014's sketch — different
    /// callers (offline transcription via `WhisperKitEngine` resamples to
    /// 16 kHz internally; future SPEC-012 streaming feeds at the engine rate)
    /// know their own rate, and the store must not assume one. The 16 kHz
    /// default preserves the spec's intent without forcing a parameter on
    /// transcript-only callers.
    public func save(audio: [Float]?,
                     audioSampleRate: Double = 16_000,
                     transcript: String,
                     language: String?,
                     modelID: String,
                     durationSeconds: TimeInterval) async throws -> HistoryEntry {
        try ensureRoot()

        let id = UUID()
        let dir = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw HistoryError.writeFailed("create \(dir.lastPathComponent): \(error)")
        }

        let recordedAt = Date()
        var meta = HistoryMeta(id: id,
                               recordedAt: recordedAt,
                               transcribedAt: nil,
                               durationSeconds: durationSeconds,
                               language: language,
                               modelID: modelID,
                               audioFormat: nil,
                               audioFilename: nil)

        var audioURL: URL?
        if let samples = audio, !samples.isEmpty {
            let result = try await Self.encodeAudio(samples,
                                                    sampleRate: audioSampleRate,
                                                    into: dir)
            audioURL = result.url
            meta.audioFormat = result.formatLabel
            meta.audioFilename = result.filename
        }

        var transcribedAt: Date?
        if !transcript.isEmpty {
            try writeTranscript(transcript, in: dir)
            transcribedAt = recordedAt
            meta.transcribedAt = transcribedAt
        }

        try writeMeta(meta, in: dir)
        applyFileProtection(to: dir)

        await enforceRetention()

        return HistoryEntry(id: id,
                            recordedAt: recordedAt,
                            transcribedAt: transcribedAt,
                            durationSeconds: durationSeconds,
                            transcript: transcript.isEmpty ? nil : transcript,
                            language: language,
                            modelID: modelID,
                            audioURL: audioURL)
    }

    // MARK: - Mark transcribed (recovery flow)

    public func markTranscribed(_ id: UUID, transcript: String) async throws {
        let dir = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw HistoryError.notFound(id)
        }
        var meta = try readMeta(in: dir)
        try writeTranscript(transcript, in: dir)
        meta.transcribedAt = Date()
        try writeMeta(meta, in: dir)
    }

    // MARK: - Queries

    /// Entries with audio still present and no `transcribedAt` — candidates
    /// for the next-launch recovery popover.
    public func recoverable() async -> [HistoryEntry] {
        return allEntries()
            .filter { $0.audioURL != nil && $0.transcribedAt == nil }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// Recent entries, newest first.
    public func list(limit: Int = 50) async -> [HistoryEntry] {
        guard limit > 0 else { return [] }
        return Array(allEntries()
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(limit))
    }

    // MARK: - Mutations

    public func delete(_ id: UUID) async throws {
        let dir = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw HistoryError.notFound(id)
        }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            throw HistoryError.writeFailed("delete \(id): \(error)")
        }
    }

    public func purgeAll() async throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: rootURL)
        } catch {
            throw HistoryError.writeFailed("purgeAll: \(error)")
        }
    }

    /// Apply the retention policy. Called after every save and on app launch.
    /// Eviction is oldest-first by `recordedAt`. Best-effort — IO errors on
    /// individual entries are swallowed so one bad directory doesn't block
    /// the rest.
    public func enforceRetention() async {
        let entries = allEntries().sorted { $0.recordedAt < $1.recordedAt }
        guard !entries.isEmpty else { return }

        let now = Date()
        var keep: [HistoryEntry] = []
        var evict: [HistoryEntry] = []

        // Pass 1: drop entries past the age cap.
        for e in entries {
            if now.timeIntervalSince(e.recordedAt) > policy.maxAge {
                evict.append(e)
            } else {
                keep.append(e)
            }
        }

        // Pass 2: enforce count cap, oldest first.
        while keep.count > policy.maxEntries {
            evict.append(keep.removeFirst())
        }

        // Pass 3: enforce size cap, oldest first.
        var sizes: [UUID: Int64] = [:]
        for e in keep { sizes[e.id] = entrySize(for: e) }
        var totalSize: Int64 = sizes.values.reduce(0, +)
        while totalSize > policy.maxBytesOnDisk, !keep.isEmpty {
            let oldest = keep.removeFirst()
            totalSize -= sizes[oldest.id] ?? 0
            evict.append(oldest)
        }

        for e in evict {
            let dir = rootURL.appendingPathComponent(e.id.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Private — directory IO

    private func ensureRoot() throws {
        do {
            try FileManager.default.createDirectory(at: rootURL,
                                                    withIntermediateDirectories: true)
        } catch {
            throw HistoryError.writeFailed("create root: \(error)")
        }
        applyFileProtection(to: rootURL)
    }

    private func allEntries() -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return [] }
        let dirs: [URL]
        do {
            dirs = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        var out: [HistoryEntry] = []
        for d in dirs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: d.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            if let entry = try? entry(from: d) {
                out.append(entry)
            }
        }
        return out
    }

    private func entry(from dir: URL) throws -> HistoryEntry {
        let meta = try readMeta(in: dir)
        let txURL = dir.appendingPathComponent("transcript.txt")
        var transcript: String?
        if FileManager.default.fileExists(atPath: txURL.path),
           let data = try? Data(contentsOf: txURL),
           let s = String(data: data, encoding: .utf8) {
            transcript = s
        }
        var audioURL: URL?
        if let filename = meta.audioFilename {
            let candidate = dir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                audioURL = candidate
            }
        }
        return HistoryEntry(id: meta.id,
                            recordedAt: meta.recordedAt,
                            transcribedAt: meta.transcribedAt,
                            durationSeconds: meta.durationSeconds,
                            transcript: transcript,
                            language: meta.language,
                            modelID: meta.modelID,
                            audioURL: audioURL)
    }

    private func readMeta(in dir: URL) throws -> HistoryMeta {
        let url = dir.appendingPathComponent("meta.json")
        do {
            let data = try Data(contentsOf: url)
            return try Self.decoder().decode(HistoryMeta.self, from: data)
        } catch {
            throw HistoryError.readFailed("\(url.lastPathComponent): \(error)")
        }
    }

    private func writeMeta(_ meta: HistoryMeta, in dir: URL) throws {
        let url = dir.appendingPathComponent("meta.json")
        do {
            let data = try Self.encoder().encode(meta)
            try data.write(to: url, options: .atomic)
        } catch {
            throw HistoryError.writeFailed("\(url.lastPathComponent): \(error)")
        }
    }

    private func writeTranscript(_ text: String, in dir: URL) throws {
        let url = dir.appendingPathComponent("transcript.txt")
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw HistoryError.writeFailed("\(url.lastPathComponent): \(error)")
        }
    }

    private func entrySize(for entry: HistoryEntry) -> Int64 {
        let dir = rootURL.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        return Self.directorySize(at: dir)
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let it = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in it {
            if let v = try? f.resourceValues(forKeys: [.fileSizeKey]),
               let bytes = v.fileSize {
                total += Int64(bytes)
            }
        }
        return total
    }

    /// `.iso8601` (no fractional seconds) collapses recordedAt timestamps
    /// from saves within the same wall-clock second to the same value, which
    /// breaks `list()`'s newest-first ordering. Use a fractional-seconds
    /// formatter so 5 ms-apart saves stay distinct on disk.
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(iso8601Fractional.string(from: date))
        }
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = iso8601Fractional.date(from: s) { return d }
            // Backward-compat for any v1-encoded files without fractional seconds.
            let plain = ISO8601DateFormatter()
            if let d = plain.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unrecognised ISO 8601 date: \(s)"
            )
        }
        return d
    }

    private func applyFileProtection(to url: URL) {
        // SPEC-014 calls for `URLResourceKey.fileProtectionKey = .complete`.
        // That attribute is iOS-only; on macOS, FileVault provides at-rest
        // protection at the volume level (which the spec already names as
        // the macOS fallback). Left as a guarded no-op so intent is recorded
        // and the call would Just Work if Apple ever extends the attribute.
        #if os(iOS) || os(tvOS) || os(watchOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        #endif
        _ = url
    }

    // MARK: - Audio encoding

    private struct EncodeResult {
        let url: URL
        let formatLabel: String
        let filename: String
    }

    /// Encode `samples` to a compressed file under `dir`. Tries Opus on
    /// macOS 14+; falls back to AAC if Opus init/finalise fails or on macOS 13.
    private static func encodeAudio(_ samples: [Float],
                                    sampleRate: Double,
                                    into dir: URL) async throws -> EncodeResult {
        if #available(macOS 14, *) {
            do {
                return try await encode(samples,
                                        sampleRate: sampleRate,
                                        into: dir,
                                        codec: kAudioFormatOpus,
                                        bitRate: 24_000,
                                        filename: "audio.caf",
                                        container: .caf,
                                        formatLabel: "opus")
            } catch {
                // Fall through to AAC.
            }
        }
        return try await encode(samples,
                                sampleRate: sampleRate,
                                into: dir,
                                codec: kAudioFormatMPEG4AAC,
                                bitRate: 32_000,
                                filename: "audio.m4a",
                                container: .m4a,
                                formatLabel: "aac")
    }

    private static func encode(_ samples: [Float],
                               sampleRate: Double,
                               into dir: URL,
                               codec: AudioFormatID,
                               bitRate: Int,
                               filename: String,
                               container: AVFileType,
                               formatLabel: String) async throws -> EncodeResult {
        let url = dir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: container)
        } catch {
            throw HistoryError.encodingFailed("AVAssetWriter init: \(error)")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey:         codec,
            AVSampleRateKey:       sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey:   bitRate,
        ]
        // `AVAssetWriterInput.init(mediaType:outputSettings:)` raises an
        // Objective-C `NSInvalidArgumentException` — not a Swift error — when the
        // settings are unsupported for this codec/container/sample-rate combo
        // (e.g. Opus at a non-48 kHz rate). A Swift `do/catch` can't intercept an
        // ObjC exception, so it would abort the process and bypass the AAC
        // fallback in `encodeAudio`. Validate first and surface a Swift error
        // instead, keeping the fallback path alive.
        guard writer.canApply(outputSettings: outputSettings, forMediaType: .audio) else {
            throw HistoryError.encodingFailed(
                "unsupported outputSettings for codec 0x\(String(codec, radix: 16)) at \(sampleRate) Hz"
            )
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw HistoryError.encodingFailed(
                "AVAssetWriter cannot add audio input for codec 0x\(String(codec, radix: 16))"
            )
        }
        writer.add(input)

        guard writer.startWriting() else {
            let msg = writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"
            throw HistoryError.encodingFailed("startWriting: \(msg)")
        }
        writer.startSession(atSourceTime: .zero)

        var asbd = AudioStreamBasicDescription(
            mSampleRate:       sampleRate,
            mFormatID:         kAudioFormatLinearPCM,
            mFormatFlags:      kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket:   4,
            mFramesPerPacket:  1,
            mBytesPerFrame:    4,
            mChannelsPerFrame: 1,
            mBitsPerChannel:   32,
            mReserved:         0
        )
        var formatDescription: CMAudioFormatDescription?
        let fdStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard fdStatus == noErr, let fd = formatDescription else {
            throw HistoryError.encodingFailed("CMAudioFormatDescriptionCreate: \(fdStatus)")
        }

        // Append in 1-second chunks (offline encoders accept data as fast
        // as it's produced, but giant single buffers are wasteful).
        let chunkFrames = max(Int(sampleRate), 1)
        var frameOffset = 0
        while frameOffset < samples.count {
            let count = min(chunkFrames, samples.count - frameOffset)
            let slice = Array(samples[frameOffset..<(frameOffset + count)])
            try appendChunk(slice,
                            startFrame: frameOffset,
                            sampleRate: sampleRate,
                            formatDescription: fd,
                            to: input)
            frameOffset += count
        }

        input.markAsFinished()
        let endTime = CMTime(value: CMTimeValue(frameOffset),
                             timescale: CMTimeScale(sampleRate))
        writer.endSession(atSourceTime: endTime)
        await writer.finishWriting()

        guard writer.status == .completed else {
            let msg = writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"
            throw HistoryError.encodingFailed("finishWriting: \(msg)")
        }

        return EncodeResult(url: url, formatLabel: formatLabel, filename: filename)
    }

    private static func appendChunk(_ samples: [Float],
                                    startFrame: Int,
                                    sampleRate: Double,
                                    formatDescription: CMAudioFormatDescription,
                                    to input: AVAssetWriterInput) throws {
        let byteCount = samples.count * MemoryLayout<Float>.size

        var blockBuffer: CMBlockBuffer?
        let bbStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard bbStatus == noErr, let bb = blockBuffer else {
            throw HistoryError.encodingFailed("CMBlockBufferCreate: \(bbStatus)")
        }

        let copyStatus: OSStatus = samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: bb,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard copyStatus == noErr else {
            throw HistoryError.encodingFailed("CMBlockBufferReplaceDataBytes: \(copyStatus)")
        }

        var sampleBuffer: CMSampleBuffer?
        let pts = CMTime(value: CMTimeValue(startFrame),
                         timescale: CMTimeScale(sampleRate))
        let sbStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: formatDescription,
            sampleCount: samples.count,
            presentationTimeStamp: pts,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let sb = sampleBuffer else {
            throw HistoryError.encodingFailed("CMAudioSampleBufferCreate: \(sbStatus)")
        }

        // Spin-wait — documented pattern for offline (`expectsMediaDataInRealTime
        // = false`) encoders. With 1-second chunks the wait is typically zero.
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.001)
        }
        guard input.append(sb) else {
            throw HistoryError.encodingFailed("AVAssetWriterInput.append returned false")
        }
    }
}
