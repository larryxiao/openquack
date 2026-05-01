import Foundation

public struct PolishCase: Codable, Sendable {
    public let id: String
    public let category: Category
    public let language: String
    public let raw: String
    public let appContext: String?
    public let references: [String]
    public let mustContain: [String]
    public let mustNotContain: [String]
    public let notes: String?

    public enum Category: String, Codable, Sendable, CaseIterable {
        case transcriptionErrors = "transcription_errors"
        case rephraseOrganize    = "rephrase_organize"
        case inContext           = "in_context"
    }

    enum CodingKeys: String, CodingKey {
        case id, category, language, raw
        case appContext = "app_context"
        case references
        case mustContain    = "must_contain"
        case mustNotContain = "must_not_contain"
        case notes
    }
}

public enum PolishCorpus {
    public static func load(at url: URL) throws -> [PolishCase] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PolishCorpus", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "corpus is not UTF-8: \(url.path)"
            ])
        }
        let dec = JSONDecoder()
        var cases: [PolishCase] = []
        for (i, raw) in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let bytes = line.data(using: .utf8) else { continue }
            do {
                cases.append(try dec.decode(PolishCase.self, from: bytes))
            } catch {
                throw NSError(domain: "PolishCorpus", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "line \(i + 1) failed to decode: \(error)"
                ])
            }
        }
        return cases
    }
}
