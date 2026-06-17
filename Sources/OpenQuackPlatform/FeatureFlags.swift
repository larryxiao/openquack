import Foundation

/// SPEC-043 — feature flags for "release behind a flag first".
///
/// New or risky features merge to `main` behind a flag that **defaults off in a
/// release**, so they ship dark and get flipped on — per test build, or for
/// everyone in a later release — once validated. This decouples *merge* from
/// *release*: the freeze/instability that caused past rollbacks can't ride out
/// to users in an unvetted feature. UserDefaults-backed, matching the app's
/// existing toggle convention; no remote-config platform.
public struct FeatureFlag: Sendable, Equatable {
    public let key: String
    /// State in a release when the user hasn't overridden it. New/risky features
    /// default `false` ("behind a flag first"); flip to `true` — or delete the
    /// flag and inline the behaviour — once the feature is proven.
    public let defaultEnabled: Bool

    public init(key: String, defaultEnabled: Bool = false) {
        self.key = key
        self.defaultEnabled = defaultEnabled
    }
}

public enum FeatureFlags {
    /// The registry. A flag is added here the moment a feature lands dark, and
    /// removed when the feature graduates. **Empty today** — alpha.20 shipped
    /// without flags by maintainer call; the next risky feature registers here,
    /// defaulting `false`.
    ///
    /// Example (when a feature lands behind a flag):
    /// ```
    /// static let cpuGpuWarm = FeatureFlag(key: "transcription.cpuGpuWarm")
    /// public static let all = [cpuGpuWarm]
    /// ```
    public static let all: [FeatureFlag] = []

    private static func storageKey(_ flag: FeatureFlag) -> String {
        "com.openquack.flag.\(flag.key)"
    }

    /// Whether `flag` is on: an explicit override if the user/build set one, else
    /// the flag's release default.
    public static func isEnabled(_ flag: FeatureFlag, defaults: UserDefaults = .standard) -> Bool {
        if let override = defaults.object(forKey: storageKey(flag)) as? Bool { return override }
        return flag.defaultEnabled
    }

    /// Override a flag (an advanced/hidden settings row, or a test build).
    public static func setEnabled(_ flag: FeatureFlag, _ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: storageKey(flag))
    }

    /// Clear an override → revert to the release default.
    public static func reset(_ flag: FeatureFlag, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(flag))
    }
}
