import Foundation

public struct PolishCase: Codable, Sendable {
    public let id: String
    public let category: Category
    public let language: String
    public let raw: String
    public let appContext: String?
    public let surroundingText: String?
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
        case appContext      = "app_context"
        case surroundingText = "surrounding_text"
        case references
        case mustContain    = "must_contain"
        case mustNotContain = "must_not_contain"
        case notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self,    forKey: .id)
        category         = try c.decode(Category.self,  forKey: .category)
        language         = try c.decode(String.self,    forKey: .language)
        raw              = try c.decode(String.self,    forKey: .raw)
        appContext       = try c.decodeIfPresent(String.self, forKey: .appContext)
        surroundingText  = try c.decodeIfPresent(String.self, forKey: .surroundingText)
        references       = try c.decode([String].self,  forKey: .references)
        mustContain      = try c.decode([String].self,  forKey: .mustContain)
        mustNotContain   = try c.decode([String].self,  forKey: .mustNotContain)
        notes            = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// Static vocabulary list loaded from JSON. Mirrors what Settings → Vocabulary
/// (and an AX/auto-mined glossary) would feed the runtime polish engine.
public struct Glossary: Sendable {
    public let terms: [String]

    public static func load(at url: URL) throws -> Glossary {
        let data = try Data(contentsOf: url)
        struct File: Decodable { let terms: [String] }
        let decoded = try JSONDecoder().decode(File.self, from: data)
        return Glossary(terms: decoded.terms)
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
