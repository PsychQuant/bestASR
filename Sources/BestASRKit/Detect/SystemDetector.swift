import Foundation

/// Detects the Apple Silicon hardware profile (spec system-detection: Detect
/// Apple Silicon hardware profile) using sysctl and process information only —
/// no external tools (design D8).
public enum SystemDetector {
    /// Raw probe values, injectable so the decision logic is testable without
    /// the host actually being (or not being) Apple Silicon.
    public struct Probe: Sendable {
        public let machineArchitecture: String
        public let isTranslated: Bool
        public let chipName: String?
        public let physicalMemoryBytes: UInt64
        public let osVersion: String

        public init(
            machineArchitecture: String,
            isTranslated: Bool,
            chipName: String?,
            physicalMemoryBytes: UInt64,
            osVersion: String
        ) {
            self.machineArchitecture = machineArchitecture
            self.isTranslated = isTranslated
            self.chipName = chipName
            self.physicalMemoryBytes = physicalMemoryBytes
            self.osVersion = osVersion
        }

        public static func live() -> Probe {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return Probe(
                machineArchitecture: sysctlString("hw.machine") ?? unameMachine(),
                isTranslated: sysctlInt32("sysctl.proc_translated") == 1,
                chipName: sysctlString("machdep.cpu.brand_string"),
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            )
        }
    }

    /// Chip generations known to ship an Apple Neural Engine. An unknown
    /// generation degrades to `nil` (unknown) rather than failing — ANE is
    /// reasoning material for the router, never a gate.
    static let aneKnownPrefixes = ["Apple M1", "Apple M2", "Apple M3", "Apple M4", "Apple M5"]

    public static func aneAvailability(forChip chip: String) -> Bool? {
        if aneKnownPrefixes.contains(where: { chip.hasPrefix($0) }) { return true }
        return nil
    }

    /// Build the hardware profile, failing clearly on non-Apple-Silicon hosts
    /// (including x86_64 processes running under Rosetta translation).
    public static func detect(probe: Probe = .live()) throws -> SystemInfo {
        guard !probe.isTranslated, probe.machineArchitecture.hasPrefix("arm64") else {
            throw BestASRError.usage(
                "bestasr requires an Apple Silicon Mac (detected architecture: "
                    + "\(probe.machineArchitecture)\(probe.isTranslated ? ", running under Rosetta" : ""))"
            )
        }
        let chip = probe.chipName ?? "Apple Silicon (unknown chip)"
        return SystemInfo(
            chip: chip,
            unifiedMemoryGB: (Double(probe.physicalMemoryBytes) / 1e9 * 10).rounded() / 10,
            hasANE: aneAvailability(forChip: chip),
            macosVersion: probe.osVersion
        )
    }

    // MARK: - sysctl helpers

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func unameMachine() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
