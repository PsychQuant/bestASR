import Foundation

/// Dynamic machine conditions read at selection time (spec system-detection:
/// Detect dynamic machine conditions, #29). Thermal serious/critical or Low
/// Power Mode count as pressure; a failed probe degrades to "no pressure" so
/// detection can never block a transcription.
public struct DynamicHostState: Sendable {
    public let thermalState: ProcessInfo.ThermalState
    public let lowPowerModeEnabled: Bool

    public init(thermalState: ProcessInfo.ThermalState, lowPowerModeEnabled: Bool) {
        self.thermalState = thermalState
        self.lowPowerModeEnabled = lowPowerModeEnabled
    }

    /// Human-readable pressure cause for explain reasons; nil when unpressured.
    /// Thermal outranks Low Power Mode when both apply (it is the more acute
    /// condition and the one the user can do least about).
    public var pressureCause: String? {
        switch thermalState {
        case .serious: return "thermal state: serious"
        case .critical: return "thermal state: critical"
        default: break
        }
        if lowPowerModeEnabled { return "Low Power Mode enabled" }
        return nil
    }

    public var isUnderPressure: Bool { pressureCause != nil }

    /// The no-pressure default. Also the value a seam SHOULD yield when it
    /// cannot determine the conditions — reads are pure synchronous value
    /// access (no I/O), so there is no runtime failure channel to catch; the
    /// injection point exists for tests and future providers (#29 verify #11/#13).
    public static let nominal = DynamicHostState(
        thermalState: .nominal, lowPowerModeEnabled: false)

    public static func probe() -> DynamicHostState {
        let info = ProcessInfo.processInfo
        return DynamicHostState(
            thermalState: info.thermalState,
            lowPowerModeEnabled: info.isLowPowerModeEnabled)
    }
}
