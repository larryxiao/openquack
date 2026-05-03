import Foundation
@_exported import OpenQuackPlatform
@_exported import OpenQuackStreaming

public enum OpenQuackKit {
    /// Re-exported from `OpenQuackPlatform.version` so existing call sites keep working.
    public static var version: String { OpenQuackPlatform.version }
}
