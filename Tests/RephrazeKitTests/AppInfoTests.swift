import Testing
@testable import RephrazeKit

// Note: swift-testing, not XCTest. XCTest ships with Xcode, which is not
// installed here -- Testing.framework comes with the toolchain itself.

@Suite("AppInfo")
struct AppInfoTests {

    @Test("Name is stable")
    func nameIsStable() {
        #expect(AppInfo.name == "Rephraze")
    }

    /// Outside the .app bundle there is no Info.plist, so these must fall back
    /// rather than crash. Guards against a force-unwrap creeping in.
    @Test("Version and build fall back outside the bundle")
    func versionFallsBack() {
        #expect(!AppInfo.version.isEmpty)
        #expect(!AppInfo.build.isEmpty)
    }

    @Test("Bundle identifier has a fallback")
    func bundleIdentifierHasFallback() {
        #expect(!AppInfo.bundleIdentifier.isEmpty)
    }
}
