import Foundation

/// Lightweight GitHub Releases poller. Hits the public `releases/latest`
/// endpoint, parses what we need, returns a `ReleaseInfo` if there's a newer
/// release than the running build. No Sparkle, no auto-install — the user
/// clicks Download and gets the DMG.
///
/// Rate limits: unauthenticated GitHub API allows 60 req/hour per IP. We poll
/// at most once per launch + once per 24h thereafter, so we're well clear.
public actor UpdateChecker {
    public struct ReleaseInfo: Sendable, Equatable {
        public let version: String          // "2.0.0-alpha.2" (no leading 'v')
        public let tagName: String          // "v2.0.0-alpha.2"
        public let pageURL: URL             // GitHub release page
        public let dmgURL: URL?             // direct DMG asset, if attached
        public let publishedAt: Date
        public let notes: String            // release body (markdown)
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case http(status: Int)
        case decode(String)
        case noReleases

        public var description: String {
            switch self {
            case .http(let s):    return "GitHub returned HTTP \(s)"
            case .decode(let m):  return "Could not decode release JSON: \(m)"
            case .noReleases:     return "Repo has no releases yet"
            }
        }
    }

    private let repo: String
    private let session: URLSession

    public init(repo: String = "larryxiao/openquack", session: URLSession = .shared) {
        self.repo = repo
        self.session = session
    }

    /// Fetch the latest release, regardless of version comparison.
    public func latest() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("OpenQuack/\(OpenQuackKit.version)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(status: -1)
        }
        if http.statusCode == 404 {
            throw Error.noReleases
        }
        guard http.statusCode == 200 else {
            throw Error.http(status: http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error.decode("not a JSON object")
        }
        guard let tagName = json["tag_name"] as? String,
              let pageStr = json["html_url"] as? String,
              let pageURL = URL(string: pageStr)
        else {
            throw Error.decode("missing tag_name / html_url")
        }
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let publishedAt = (json["published_at"] as? String).flatMap(Self.parseDate) ?? Date()
        let notes = (json["body"] as? String) ?? ""

        var dmgURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      name.lowercased().hasSuffix(".dmg"),
                      let dl = asset["browser_download_url"] as? String,
                      let url = URL(string: dl)
                else { continue }
                dmgURL = url
                break
            }
        }

        return ReleaseInfo(
            version: version,
            tagName: tagName,
            pageURL: pageURL,
            dmgURL: dmgURL,
            publishedAt: publishedAt,
            notes: notes
        )
    }

    /// Returns `ReleaseInfo` iff its version is strictly newer than `currentVersion`.
    public func checkForUpdate(currentVersion: String) async throws -> ReleaseInfo? {
        let info = try await latest()
        return Self.isNewer(remote: info.version, than: currentVersion) ? info : nil
    }

    /// SemVer-2.0.0 precedence comparison. Returns true iff `remote` is a
    /// strictly newer release than `current`.
    ///
    /// The old `.numeric` string compare got three cases wrong, all of which
    /// could pin the update badge "on" forever:
    ///   • prerelease ordering — "2.0.0-alpha.2" sorted *after* "...alpha.16"
    ///     lexically, so an older advertised build looked newer.
    ///   • release vs prerelease — "2.0.0" must outrank "2.0.0-alpha.16"; the
    ///     prefix compare reported the opposite.
    ///   • differently-formatted-but-equal versions never compared equal.
    static func isNewer(remote: String, than current: String) -> Bool {
        let r = remote.hasPrefix("v") ? String(remote.dropFirst()) : remote
        let c = current.hasPrefix("v") ? String(current.dropFirst()) : current
        return compareSemver(r, c) == .orderedDescending
    }

    /// SemVer-2.0.0 precedence (build metadata after `+` is ignored — we emit
    /// none). Tolerant of short cores like "2.0" (missing parts read as 0).
    static func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let (coreA, preA) = splitPrerelease(a)
        let (coreB, preB) = splitPrerelease(b)

        // 1. Core: major.minor.patch, numeric, missing components are 0.
        let na = coreA.split(separator: ".").map { Int($0) ?? 0 }
        let nb = coreB.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(na.count, nb.count) {
            let x = i < na.count ? na[i] : 0
            let y = i < nb.count ? nb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }

        // 2. A version with NO prerelease tag outranks one that has it.
        switch (preA.isEmpty, preB.isEmpty) {
        case (true, true):  return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): break
        }

        // 3. Compare prerelease identifiers left to right.
        let idA = preA.split(separator: ".").map(String.init)
        let idB = preB.split(separator: ".").map(String.init)
        for i in 0..<max(idA.count, idB.count) {
            // Fewer identifiers, all else equal, ranks lower.
            guard i < idA.count else { return .orderedAscending }
            guard i < idB.count else { return .orderedDescending }
            let x = idA[i], y = idB[i]
            if x == y { continue }
            switch (Int(x), Int(y)) {
            case let (xi?, yi?): return xi < yi ? .orderedAscending : .orderedDescending
            case (_?, nil):      return .orderedAscending   // numeric < alphanumeric
            case (nil, _?):      return .orderedDescending
            case (nil, nil):     return x < y ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func splitPrerelease(_ v: String) -> (core: String, pre: String) {
        let noBuild = v.split(separator: "+", maxSplits: 1).first.map(String.init) ?? v
        guard let dash = noBuild.firstIndex(of: "-") else { return (noBuild, "") }
        return (String(noBuild[..<dash]), String(noBuild[noBuild.index(after: dash)...]))
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
