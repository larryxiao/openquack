import Foundation

/// How OpenQuack got onto this Mac. Determines which upgrade path the
/// in-app update banner offers.
public enum InstallMethod: Sendable, Equatable {
    /// Installed via `brew install --cask openquack`. The `.app` lives
    /// under `${HOMEBREW_PREFIX}/Caskroom/openquack/<version>/` and
    /// `/Applications/OpenQuack.app` is a symlink into that.
    case homebrew(prefix: String)

    /// Drag-installed (DMG → Applications) or anything else. Default.
    case manual

    /// Whether `brew upgrade --cask openquack` is the right call.
    public var isBrew: Bool {
        if case .homebrew = self { return true }
        return false
    }
}

public enum InstallMethodDetector {
    /// Inspects the running .app's path to figure out whether brew owns
    /// it. Cheap — symlink resolution + a single FileManager check, no
    /// subprocesses.
    public static func detect(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> InstallMethod {
        // Resolve symlinks. Brew's Caskroom layout: the .app at
        // /Applications/OpenQuack.app is a symlink whose target is
        // ${HOMEBREW_PREFIX}/Caskroom/openquack/<version>/OpenQuack.app.
        let resolved = bundleURL.resolvingSymlinksInPath().path
        if resolved.contains("/Caskroom/openquack/") {
            // Walk up to find the brew prefix (the parent of "Caskroom").
            let parts = resolved.components(separatedBy: "/Caskroom/")
            if let prefix = parts.first, !prefix.isEmpty {
                return .homebrew(prefix: prefix)
            }
        }

        // Belt-and-braces: even if we're running from /Applications
        // directly (e.g. brew installed alongside a stale manual copy),
        // a same-named cask metadata dir means brew thinks it owns this
        // install.
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let metadata = "\(prefix)/Caskroom/openquack/.metadata"
            if fileManager.fileExists(atPath: metadata) {
                return .homebrew(prefix: prefix)
            }
        }

        return .manual
    }
}
