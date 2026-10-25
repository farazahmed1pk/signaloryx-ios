import Foundation
import Darwin

/// No device name, IDFV, advertising ID, location or network identifiers.
internal func deviceMetadata() -> [String: String] {
    let process = ProcessInfo.processInfo
    let version = process.operatingSystemVersion
    var system = utsname()
    uname(&system)
    let machine = withUnsafePointer(to: &system.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
    }
    var values = [
        "os.name": "iOS", "os.version": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
        "device.model": machine,
        "device.memory_total_bytes": String(process.physicalMemory),
        "runtime.cpu_count": String(process.activeProcessorCount),
        "runtime.low_power_mode": String(process.isLowPowerModeEnabled),
        "runtime.thermal_state": String(process.thermalState.rawValue),
        "locale": Locale.current.identifier, "timezone": TimeZone.current.identifier,
        "sdk.name": "signaloryx-ios"
    ]
    #if os(macOS)
    values["os.name"] = "macOS"
    #endif
    let bundle = Bundle.main
    values["app.identifier"] = bundle.bundleIdentifier
    values["app.version"] = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    values["app.build"] = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    #if targetEnvironment(simulator)
    values["device.simulator"] = "true"
    #else
    values["device.simulator"] = "false"
    #endif
    return values.mapValues { String($0.prefix(256)) }
}
