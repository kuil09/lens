import AppKit
import Testing
@testable import Lens

@Test @MainActor func aboutVersionUsesArtifactMetadataAndHandlesUnbundledDevelopment() {
    let info = LensReleaseInfo(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "LensReleaseChannel": "beta.1"])
    #expect(info.displayVersion == "0.1.0-beta.1")
    #expect(info.aboutOptions[.version] as? String == "1")
    #expect(LensReleaseInfo(info: ["CFBundleShortVersionString": "0.1.0"]).displayVersion == "0.1.0")
    #expect(LensReleaseInfo(info: [:]).displayVersion == L10n.text("Development Build"))
    #expect(LensReleaseInfo(info: ["CFBundleShortVersionString": "$(MARKETING_VERSION)"]).displayVersion == L10n.text("Development Build"))
}

@Test func privacyManifestDeclaresOnlyLocalSettingsAndElapsedTime() throws {
    // Check the tracked manifest; the release script also validates its bundled copy.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Sources/Lens/Resources/PrivacyInfo.xcprivacy"))
    let manifest = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(manifest["NSPrivacyTracking"] as? Bool == false)
    #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    let categories = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    #expect(categories.count == 2)
    let reasons = Dictionary(uniqueKeysWithValues: try categories.map {
        (try #require($0["NSPrivacyAccessedAPIType"] as? String), try #require($0["NSPrivacyAccessedAPITypeReasons"] as? [String]))
    })
    #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])
    #expect(reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"])
}
