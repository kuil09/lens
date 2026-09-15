import AppKit

/// Reads the built artifact, not a duplicated hard-coded release version.
struct LensReleaseInfo {
    let version: String
    let build: String
    let channel: String

    init(info: [String: Any]) {
        func value(_ key: String) -> String {
            guard let string = info[key] as? String, !string.contains("$(") else { return "" }
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        version = value("CFBundleShortVersionString")
        build = value("CFBundleVersion")
        channel = value("LensReleaseChannel")
    }

    var displayVersion: String {
        guard !version.isEmpty else { return L10n.text("Development Build") }
        return channel.isEmpty ? version : "\(version)-\(channel)"
    }

    @MainActor var aboutOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: "Lens",
            .applicationVersion: displayVersion,
            .version: build,
            .credits: NSAttributedString(string: L10n.text("On-device translation over your screen\nMIT License · github.com/kuil09/lens"))
        ]
    }
}
