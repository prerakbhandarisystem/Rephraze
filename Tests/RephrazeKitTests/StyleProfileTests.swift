import Foundation
import Testing
@testable import RephrazeKit

// Note: swift-testing, not XCTest. XCTest ships with Xcode, which is not
// installed here -- Testing.framework comes with the toolchain itself.

@Suite("StyleProfile")
struct StyleProfileTests {

    private func sample(name: String = "House voice") -> StyleProfile {
        StyleProfile(
            name: name,
            describedStyle: "Short sentences. No exclamation marks.",
            answers: ["length": ["short"], "warmth": ["plain", "direct"]]
        )
    }

    @Test("A profile survives the round trip")
    func roundTrips() throws {
        let original = sample()
        let decoded = try StyleProfile.decoded(from: original.encoded())

        #expect(decoded.name == original.name)
        #expect(decoded.describedStyle == original.describedStyle)
        #expect(decoded.answers == original.answers)
    }

    /// These files get pasted into chat threads and committed to repositories.
    /// Two exports of the same voice must produce the same bytes, or a diff
    /// shows that something changed rather than what.
    @Test("The same profile encodes to the same bytes")
    func encodingIsStable() throws {
        let profile = sample()
        #expect(try profile.encoded() == profile.encoded())
    }

    @Test("Anything that is not a profile is refused")
    func rejectsRubbish() {
        #expect(throws: StyleProfile.ProfileError.self) {
            try StyleProfile.decoded(from: Data("not a profile".utf8))
        }
    }

    /// Refused rather than half-imported. A profile whose extra fields we
    /// silently dropped would be a voice quietly different from the sender's.
    @Test("A profile from a newer format is refused, not partly read")
    func rejectsNewerFormats() throws {
        var future = sample()
        future.version = StyleProfile.currentVersion + 1

        #expect(throws: StyleProfile.ProfileError.self) {
            try StyleProfile.decoded(from: future.encoded())
        }
    }

    @Test("The filename says what it holds")
    func filenameIsUseful() {
        #expect(sample(name: "Support replies").suggestedFilename
            == "Support replies.\(StyleProfile.fileExtension)")
    }

    /// An unnamed profile still has to save somewhere, rather than producing a
    /// file called ".rephrazestyle" that Finder hides.
    @Test("An empty name still yields a filename")
    func emptyNameStillNamesTheFile() {
        #expect(sample(name: "   ").suggestedFilename
            == "Writing style.\(StyleProfile.fileExtension)")
    }
}
