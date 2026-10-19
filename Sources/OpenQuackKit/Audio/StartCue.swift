import AVFoundation
import Foundation

/// SPEC-010 — how long the record-start cue is actually audible. System sounds
/// pad a short click with silence (Tink: ~50 ms of sound in a 0.56 s file), so
/// waiting the file's full duration before opening the mic is dead time.
public enum StartCue {

    /// Samples quieter than this, relative to the file's peak, count as silence.
    public static let silenceBelowPeak: Float = 0.001   // −60 dB

    /// Seconds from the start of `url` to its last audible sample, or nil when
    /// the file can't be read.
    public static func audibleDuration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url),
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData
        else { return nil }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var peak: Float = 0
        for c in 0..<channelCount {
            for i in 0..<frames { peak = max(peak, abs(channels[c][i])) }
        }
        guard peak > 0 else { return 0 }

        let floor = peak * silenceBelowPeak
        var lastAudible = 0
        for c in 0..<channelCount {
            for i in stride(from: frames - 1, through: lastAudible, by: -1) where abs(channels[c][i]) > floor {
                lastAudible = i
                break
            }
        }
        return Double(lastAudible + 1) / buffer.format.sampleRate
    }

    /// Where a named system sound lives, searched the way `NSSound(named:)` does.
    public static func systemSoundURL(named name: String) -> URL? {
        let dirs = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds"),
            URL(fileURLWithPath: "/Library/Sounds"),
            URL(fileURLWithPath: "/System/Library/Sounds"),
        ]
        for dir in dirs {
            for ext in ["aiff", "aif", "wav", "caf"] {
                let url = dir.appendingPathComponent(name).appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
}
