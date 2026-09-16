import AppKit

/// Export ownership is independent of permission/window-return policy.
@MainActor final class LensExportCoordinator {
    struct Scene {
        let background: CGImage
        let pointSize: CGSize
        let translations: [DisplayTranslation]
        let opacity: Double
        @MainActor func image() -> CGImage? {
            LensSnapshot.image(background: background, pointSize: pointSize,
                               translations: translations, maskOpacity: opacity)
        }
    }
    let recording = LensRecording()
    let store: LensExportStore
    let feedback = LensCaptureFeedback()
    private let scene: @MainActor () -> Scene?
    private let recordingFrame: (@MainActor () -> RecordingFrame?)?
    private(set) var directoryPanel: NSOpenPanel? { didSet { onChoosingDirectoryChanged?() } }
    var onStatus: ((String) -> Void)?
    var onError: ((Error, String) -> Void)?
    var onChoosingDirectoryChanged: (() -> Void)?

    init(store: LensExportStore = LensExportStore(), recordingFrame: (@MainActor () -> RecordingFrame?)? = nil,
         scene: @escaping @MainActor () -> Scene?) {
        self.store = store; self.scene = scene
        self.recordingFrame = recordingFrame
        recording.onSaved = { [weak store] in store?.didSave($0) }
    }
    func toggleRecording() {
        if recording.isRecording { recording.stop(); return }
        guard !recording.isFinishing, directoryPanel == nil else { return }
        do {
            if let recordingFrame {
                guard let first = recordingFrame() else { return }
                try recording.start(destination: store.videoDestination(), firstFrame: first)
            } else {
                guard let image = scene()?.image() else { return }
                try recording.start(destination: store.videoDestination(), firstFrame: image,
                                    frame: { [weak self] in self?.scene()?.image() })
            }
        } catch { onError?(error, L10n.text("Could Not Save")) }
    }
    func saveCapture() {
        feedback.beginAttempt()
        guard directoryPanel == nil else { return }
        guard let scene = scene(), let data = LensSnapshot.png(background: scene.background,
            pointSize: scene.pointSize, translations: scene.translations, maskOpacity: scene.opacity) else {
            onStatus?(L10n.text("No captured screen to save. Start translation and wait for the screen to connect."))
            return
        }
        do {
            let url = try store.saveImage(data)
            feedback.didSave()
            onStatus?(L10n.text("Image saved · %1$@", String(describing: url.lastPathComponent)))
        } catch { onError?(error, L10n.text("Could Not Save")) }
    }
    func openDirectory() {
        do { try store.openDirectory(using: { NSWorkspace.shared.open($0) }) }
        catch { onError?(error, L10n.text("Could Not Open Save Folder")) }
    }
    func chooseDirectory(parent: NSWindow?) {
        if let directoryPanel { directoryPanel.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Capture Save Folder")
        panel.message = L10n.text("Images and videos are saved to this folder automatically.")
        panel.prompt = L10n.text("Choose Folder")
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = store.directory
        directoryPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self else { return }
            let url = panel?.url
            directoryPanel = nil
            guard response == .OK, let url else { return }
            do { try store.selectDirectory(url) }
            catch { onError?(error, L10n.text("Could Not Save")) }
        }
        if let parent { panel.beginSheetModal(for: parent, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func cancelDirectorySelection() { directoryPanel?.cancel(nil) }

    isolated deinit {
        directoryPanel?.cancel(nil)
        // Finish an owned recording even if the coordinator is released unexpectedly.
        // LensRecording retains only its bounded finalization task until publication.
        recording.stop()
    }
}
