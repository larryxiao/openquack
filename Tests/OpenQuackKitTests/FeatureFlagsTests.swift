import XCTest
@testable import OpenQuackPlatform

/// SPEC-043 — feature-flag resolution (override beats default; reset reverts).
final class FeatureFlagsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Isolated store so tests never touch the real app defaults.
        defaults = UserDefaults(suiteName: "FeatureFlagsTests")!
        defaults.removePersistentDomain(forName: "FeatureFlagsTests")
    }

    func testDefaultOff_whenNoOverride() {
        let f = FeatureFlag(key: "x.off")  // defaults false
        XCTAssertFalse(FeatureFlags.isEnabled(f, defaults: defaults))
    }

    func testDefaultOn_whenDeclaredOn() {
        let f = FeatureFlag(key: "x.on", defaultEnabled: true)
        XCTAssertTrue(FeatureFlags.isEnabled(f, defaults: defaults))
    }

    func testOverrideBeatsDefault_bothDirections() {
        let off = FeatureFlag(key: "x.a")             // default false
        FeatureFlags.setEnabled(off, true, defaults: defaults)
        XCTAssertTrue(FeatureFlags.isEnabled(off, defaults: defaults))

        let on = FeatureFlag(key: "x.b", defaultEnabled: true)
        FeatureFlags.setEnabled(on, false, defaults: defaults)
        XCTAssertFalse(FeatureFlags.isEnabled(on, defaults: defaults))
    }

    func testReset_revertsToDefault() {
        let f = FeatureFlag(key: "x.c")  // default false
        FeatureFlags.setEnabled(f, true, defaults: defaults)
        XCTAssertTrue(FeatureFlags.isEnabled(f, defaults: defaults))
        FeatureFlags.reset(f, defaults: defaults)
        XCTAssertFalse(FeatureFlags.isEnabled(f, defaults: defaults))
    }
}
