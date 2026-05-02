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

/// Loads `{"terms": [...]}` from JSON. Just a list of strings — there is no
/// "Glossary" concept at the architectural level; the terms are the vocabulary
/// slot inside the system prompt.
public enum VocabularyFile {
    public static func load(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        struct File: Decodable { let terms: [String] }
        return try JSONDecoder().decode(File.self, from: data).terms
    }
}

/// User profile fed into the polish prompt. Higher-density context than a
/// flat vocabulary list — domain + style + projects let the model disambiguate
/// in cases where vocabulary alone can't (semantic ambiguity, not acoustic;
/// acoustic disambiguation belongs to Whisper's prompt biasing).
public struct UserProfile: Codable, Sendable {
    public let domain: String?
    public let languages: [String]?
    public let primaryLanguage: String?
    public let projects: [String]?
    public let style: String?
    public let commonApps: [String: String]?

    enum CodingKeys: String, CodingKey {
        case domain, languages, projects, style
        case primaryLanguage = "primary_language"
        case commonApps      = "common_apps"
    }

    public func renderForPrompt() -> String {
        var lines: [String] = []
        if let d = domain { lines.append("Domain: \(d)") }
        if let p = projects, !p.isEmpty {
            let joined = p.joined(separator: "; ")
            lines.append("Projects: \(joined)")
        }
        if let s = style { lines.append("Style: \(s)") }
        if let langs = languages, !langs.isEmpty {
            let primary = primaryLanguage.map { " (primary: \($0))" } ?? ""
            let joined = langs.joined(separator: ", ")
            lines.append("Languages: \(joined)\(primary)")
        }
        if let apps = commonApps, !apps.isEmpty {
            let pairs = apps.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }
            let joined = pairs.joined(separator: "; ")
            lines.append("Typical apps: \(joined)")
        }
        return lines.joined(separator: "\n")
    }

    public static func load(at url: URL) throws -> UserProfile {
        let data = try Data(contentsOf: url)
        struct File: Decodable { let profile: UserProfile }
        return try JSONDecoder().decode(File.self, from: data).profile
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
