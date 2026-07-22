import Foundation

/// Platform-only utilities: host detection, memory sampling, version stamp.
/// Carries no UI / KeyboardShortcuts / WhisperKit deps so the bench targets
/// can build without Xcode-only macro plugins.
public enum OpenQuackPlatform {
    public static let version = "2.0.0-alpha.22"
}
