import Foundation

/// Display metadata for the Whisper speech-model variants offered in the
/// Settings picker. Pure lookups — used by the download sheet, the menu-bar
/// banner, and `SpeechModelDownloadController` so the strings live in one
/// place. The byte-accurate download is owned by WhisperKit; these are the
/// human-facing labels only.
public enum SpeechModelCatalog {
    /// The variants offered in Settings, in display order.
    public static let all = ["tiny", "base", "small", "medium", "large-v3"]

    public static func displayName(for variant: String) -> String {
        switch variant {
        case "tiny":     return "Tiny"
        case "base":     return "Base"
        case "small":    return "Small"
        case "medium":   return "Medium"
        case "large-v3": return "Large v3"
        default:         return variant
        }
    }

    public static func sizeLabel(for variant: String) -> String {
        switch variant {
        case "tiny":     return "~150 MB"
        case "base":     return "~290 MB"
        case "small":    return "~480 MB"
        case "medium":   return "~1.5 GB"
        case "large-v3": return "~3 GB"
        default:         return "the model"
        }
    }
}
