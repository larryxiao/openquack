import Foundation
import Darwin

public struct HostInfo: Codable, Sendable {
    public let chip: String
    public let coreCount: Int
    public let gpuCoreCount: Int?       // nil if not detected
    public let memoryGB: Double
    public let macOSVersion: String
    /// Compact, filesystem-safe identifier, e.g. "M3-Max-36GB". Use this in
    /// `bench/out/<host-tag>/` so per-machine reports don't collide.
    public let hostTag: String

    public static func detect() -> HostInfo {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Unknown"
        let cores = Int(sysctlInt("hw.ncpu") ?? 0)
        let memBytes = sysctlInt("hw.memsize") ?? 0
        let memGB = Double(memBytes) / 1_073_741_824.0
        let macOSVer = ProcessInfo.processInfo.operatingSystemVersionString
        let gpuCores = parseGPUCores()
        let hostTag = makeHostTag(chip: chip, memGB: memGB)

        return HostInfo(
            chip: chip,
            coreCount: cores,
            gpuCoreCount: gpuCores,
            memoryGB: memGB,
            macOSVersion: macOSVer,
            hostTag: hostTag
        )
    }

    private static func makeHostTag(chip: String, memGB: Double) -> String {
        var tag = chip
            .replacingOccurrences(of: "Apple ", with: "")
            .replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
        // Collapse whitespace, replace with hyphens.
        tag = tag.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        if tag.isEmpty { tag = "Unknown" }
        let mem = Int(memGB.rounded())
        return "\(tag)-\(mem)GB"
    }
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    if sysctlbyname(name, nil, &size, nil, 0) != 0 || size == 0 { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    if sysctlbyname(name, &buffer, &size, nil, 0) != 0 { return nil }
    return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sysctlInt(_ name: String) -> Int64? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
}

private func parseGPUCores() -> Int? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    p.arguments = ["SPDisplaysDataType", "-json"]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do {
        try p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let displays = json["SPDisplaysDataType"] as? [[String: Any]]
        else { return nil }
        for display in displays {
            if let cores = display["sppci_cores"] as? String, let n = Int(cores) {
                return n
            }
        }
    } catch {
        return nil
    }
    return nil
}
