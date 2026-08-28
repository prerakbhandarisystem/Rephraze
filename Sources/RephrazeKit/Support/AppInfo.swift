import Foundation

/// Identity of the running app, read from the bundle's Info.plist.
public enum AppInfo {
    public static let name = "Rephraze"

    /// Where the Support section sends a report. One place to change it.
    public static let supportEmail = "prerakbhandari@gmail.com"

    /// Where opt-in usage reports are sent, or `nil` for a build that collects
    /// nothing at all.
    ///
    /// Unset on purpose. Until this points somewhere, `Telemetry` records
    /// nothing, the Settings section says so, and the app cannot phone home
    /// even if the toggle is on. Set it when the server in `telemetry/` is
    /// actually running, e.g.
    /// `URL(string: "https://usage.example.com/v1/events")`.
    public static let usageEndpoint: URL? = nil

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Stable across rebuilds — this is what the Accessibility grant is tied to,
    /// alongside the code signature.
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.prerak.rephraze"
    }
}
