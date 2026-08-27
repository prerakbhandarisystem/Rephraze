import Foundation

/// Identity of the running app, read from the bundle's Info.plist.
public enum AppInfo {
    public static let name = "Rephraze"

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
