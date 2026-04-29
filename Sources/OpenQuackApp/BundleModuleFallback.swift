import Foundation
import Darwin
import ObjectiveC
import os.log

private let oqLog = OSLog(subsystem: "org.openquack.OpenQuack", category: "BundleModuleFallback")

// SwiftPM auto-generates a `Bundle.module` accessor in every package that
// declares `resources:` (KeyboardShortcuts, swift-transformers/Hub, the
// swift-crypto trio). The generator hardcodes two lookup paths, both
// broken for a shipped .app:
//
//   1. `Bundle.main.bundleURL.appendingPathComponent("<name>.bundle")`
//      — for an .app, that's the .app *root*, where codesign refuses
//      to seal extra content alongside `Contents/`.
//   2. An absolute path to whoever-built-it's `.build/release/` —
//      exists on the dev Mac, doesn't exist anywhere else. Tahoe
//      enforces this where earlier macOS sometimes did not, so the
//      `Swift.fatalError` at the end of the accessor fires as SIGTRAP
//      the moment any code path touches `Bundle.module`
//      (`KeyboardShortcuts.RecorderCocoa.init` is the usual trigger).
//
// `wrap_app.sh` puts the bundles where they belong —
// `<App.app>/Contents/Resources/<name>.bundle` (codesign-clean). This
// swizzle redirects probe (1) there: when the SwiftPM accessor calls
// `Bundle(path: "<App.app>/<name>.bundle")`, we transparently rewrite
// the path to `<App.app>/Contents/Resources/<name>.bundle` before the
// underlying NSBundle init runs. Works for any install location —
// `/Applications`, `~/Applications`, `/tmp`, doesn't matter.
//
// Done as a swizzle because SwiftPM regenerates the accessor source on
// every build, so editing the .swift file in-tree doesn't survive.
//
// We must NOT touch `Bundle.main` from inside the IMP — its internals
// call `-[NSBundle initWithPath:]`, which is the selector we swizzle,
// so any `Bundle.*` access from the IMP is infinite recursion. The .app
// root is derived from `_NSGetExecutablePath` instead, captured once
// before the swizzle is installed.
enum BundleModuleFallback {
    static func install() {
        _ = swizzleOnce
    }

    fileprivate static let appRootPrefix: String = appRoot + "/"
    fileprivate static let resourcesRoot: String = appRoot + "/Contents/Resources"

    private static let appRoot: String = {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return "" }
        let exePath = String(cString: buffer)
        // For an .app: <root>/<Name>.app/Contents/MacOS/<exe>
        // We want <root>/<Name>.app — drop three trailing components.
        return (exePath as NSString)
            .deletingLastPathComponent  // .../Contents/MacOS
            .deletingLastPathComponent  // .../Contents
            .deletingLastPathComponent  // .../<Name>.app
    }()

    private static let swizzleOnce: Void = {
        _ = appRootPrefix
        _ = resourcesRoot
        let cls: AnyClass = Bundle.self
        let originalSelector = NSSelectorFromString("initWithPath:")
        let replacementSelector = #selector(Bundle.oq_initWithPath(_:))
        guard let original = class_getInstanceMethod(cls, originalSelector),
              let replacement = class_getInstanceMethod(cls, replacementSelector) else {
            os_log("swizzle install FAILED — Bundle.init(path:) not found", log: oqLog, type: .error)
            assertionFailure("BundleModuleFallback: Bundle.init(path:) not found for swizzle")
            return
        }
        method_exchangeImplementations(original, replacement)
        os_log("swizzle installed; appRoot=%{public}@ resourcesRoot=%{public}@",
               log: oqLog, type: .info, appRootPrefix, resourcesRoot)
    }()
}

private extension String {
    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
}

extension Bundle {
    @objc fileprivate func oq_initWithPath(_ path: String) -> Bundle? {
        let prefix = BundleModuleFallback.appRootPrefix
        if !prefix.isEmpty, path.hasPrefix(prefix) {
            let trailing = String(path.dropFirst(prefix.count))
            // Match the exact SwiftPM probe shape — single-component
            // <name>.bundle directly at the .app root. Any deeper path
            // is something else and shouldn't be touched.
            if !trailing.contains("/"), trailing.hasSuffix(".bundle") {
                let redirected = BundleModuleFallback.resourcesRoot + "/" + trailing
                return self.oq_initWithPath(redirected)
            }
        }
        // After method_exchangeImplementations the original IMP lives
        // under our selector, so this call invokes NSBundle's real init.
        return self.oq_initWithPath(path)
    }
}
