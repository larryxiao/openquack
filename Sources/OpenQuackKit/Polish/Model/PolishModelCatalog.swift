import Foundation

/// Single source of truth for the polish model to fetch; the seam for a future multi-model picker.
public enum PolishModelCatalog {
    public static let remoteURL = URL(string:
        "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf")!
    public static let filename = "gemma-4-E2B-it-Q4_K_M.gguf"
    public static let expectedBytes: Int64 = 3_106_736_256
    public static let licenseURL = URL(string: "https://ai.google.dev/gemma/docs/gemma_4_license")!
    public static let displayName = "Gemma 4 E2B"
    public static let sizeLabel = "~2.9 GB"

    /// `~/Library/Application Support/OpenQuack/models/<filename>`.
    public static var localURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenQuack/models", isDirectory: true)
            .appendingPathComponent(filename)
    }

    public static func isInstalled() -> Bool {
        isInstalled(at: localURL)
    }

    static func isInstalled(at url: URL, expectedBytes: Int64 = expectedBytes) -> Bool {
        fileSize(url) == expectedBytes
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return n.int64Value
    }
}
