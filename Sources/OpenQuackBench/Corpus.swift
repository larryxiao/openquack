import Foundation

public struct Clip {
    public let id: String
    public let url: URL
    public let reference: String
}

public enum Corpus {
    /// Walks `directory` recursively and pairs each `<name>.{wav,mp3,flac,m4a}` with
    /// `<name>.txt` (its reference transcript). Audio files without a matching `.txt`
    /// are skipped silently — keeps the corpus tolerant of partial downloads.
    public static func load(at directory: URL) throws -> [Clip] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory,
                                             includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else {
            return []
        }
        var clips: [Clip] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ["wav", "mp3", "flac", "m4a"].contains(ext) else { continue }
            let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
            guard fm.fileExists(atPath: txtURL.path) else { continue }
            let raw = try String(contentsOf: txtURL, encoding: .utf8)
            let reference = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = url.deletingPathExtension().lastPathComponent
            clips.append(Clip(id: id, url: url, reference: reference))
        }
        return clips.sorted { $0.id < $1.id }
    }
}
