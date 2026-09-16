import AppKit
import AVFoundation
import Combine
import CoreImage
import Testing
@testable import Lens

@MainActor private final class NotificationCounter { var count = 0 }
@Test @MainActor func observationBagRemovesTokensFromTheirIssuingCenters() {
    let first = NotificationCenter(), second = NotificationCenter()
    let name = Notification.Name("LensSyntheticNotice")
    let counter = NotificationCounter()
    var bag: LensObservationBag? = LensObservationBag()
    for center in [first, second] {
        bag?.observe(center, name: name) { _ in MainActor.assumeIsolated { counter.count += 1 } }
        center.post(name: name, object: nil)
    }
    #expect(counter.count == 2)
    bag?.cancel(); bag?.cancel(); bag = nil
    first.post(name: name, object: nil); second.post(name: name, object: nil)
    #expect(counter.count == 2)
    // Releasing the owner without an explicit cancel must remove its token too.
    bag = LensObservationBag()
    bag?.observe(second, name: name) { _ in MainActor.assumeIsolated { counter.count += 1 } }
    second.post(name: name, object: nil)
    #expect(counter.count == 3)
    bag = nil
    second.post(name: name, object: nil)
    #expect(counter.count == 3)
}

@Test @MainActor func exportCoordinatorClearsSuccessWhenNextSceneIsMissing() throws {
    let name = "LensHousekeeping-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
    let image = try #require(CIContext().createCGImage(CIImage(color: .white), from: CGRect(x: 0, y: 0, width: 100, height: 100)))
    var available = true
    let store = LensExportStore(defaults: defaults, defaultDirectory: root)
    let coordinator = LensExportCoordinator(store: store, scene: {
        available ? .init(background: image, pointSize: CGSize(width: 100, height: 100), translations: [], opacity: 1) : nil
    })
    coordinator.saveCapture()
    #expect(coordinator.feedback.showsSuccess)
    #expect(store.lastSavedURL != nil)
    available = false
    coordinator.saveCapture()
    #expect(!coordinator.feedback.showsSuccess)
    coordinator.toggleRecording()
    #expect(!coordinator.recording.isRecording)
}

@Test @MainActor func releasingExportOwnerFinalizesItsRecordingWithoutRestarting() async throws {
    let name = "LensExportOwner-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
    let image = try #require(CIContext().createCGImage(CIImage(color: .white),
        from: CGRect(x: 0, y: 0, width: 160, height: 100)))
    let store = LensExportStore(defaults: defaults, defaultDirectory: root)
    var coordinator: LensExportCoordinator? = LensExportCoordinator(store: store, scene: {
        .init(background: image, pointSize: CGSize(width: 160, height: 100), translations: [], opacity: 1)
    })
    let recording = try #require(coordinator?.recording)
    coordinator?.toggleRecording()
    #expect(recording.isRecording)
    weak var released = coordinator
    coordinator = nil
    #expect(released == nil && !recording.isRecording)
    let finish = try #require(recording.stop())
    await finish.value
    #expect(!recording.isFinishing && recording.stop() == nil)
    let url = try #require(store.lastSavedURL)
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    #expect(reader.startReading())
    #expect(output.copyNextSampleBuffer() != nil)
    reader.cancelReading()
}

@MainActor private final class MenuTarget: NSObject {
    @objc func idle() {}
    @objc func capture() {}
    @objc func recording() {}
    @objc func toggle() {}
}
@Test @MainActor func extractedMenusPreserveTargetsShortcutsAndReplaceStatusItem() throws {
    _ = NSApplication.shared
    let previous = (NSApp.mainMenu, NSApp.servicesMenu, NSApp.windowsMenu, NSApp.helpMenu)
    defer {
        NSApp.mainMenu = previous.0; NSApp.servicesMenu = previous.1
        NSApp.windowsMenu = previous.2; NSApp.helpMenu = previous.3
    }
    let controller = LensMenuController(), target = MenuTarget()
    let idle = #selector(MenuTarget.idle)
    let actions = LensMenuController.Actions(showAbout: idle, showSettings: idle,
        saveCapture: #selector(MenuTarget.capture), toggleRecording: #selector(MenuTarget.recording),
        openExportDirectory: idle, showLens: idle, showReader: idle, focusOverflow: idle,
        toggle: #selector(MenuTarget.toggle), toggleLock: idle, showHelp: idle,
        showOnboarding: idle, showPreparation: idle)
    controller.install(target: target, actions: actions)
    let items = try #require(NSApp.mainMenu).items.flatMap { $0.submenu?.items ?? [] }
    let capture = try #require(items.first { $0.action == #selector(MenuTarget.capture) })
    #expect(capture.target === target && capture.keyEquivalent == "s")
    #expect(capture.keyEquivalentModifierMask == [.command, .shift])
    let recording = try #require(items.first { $0.action == #selector(MenuTarget.recording) })
    #expect(recording.target === target && recording.keyEquivalent == "r")
    #expect(recording.keyEquivalentModifierMask == [.command, .shift])
    let toggle = try #require(items.first { $0.action == #selector(MenuTarget.toggle) })
    #expect(toggle.target === target && toggle.keyEquivalentModifierMask == .command)
    let original = controller.statusItem
    controller.install(target: target, actions: actions)
    #expect(controller.statusItem !== original)
    #expect(controller.statusItem?.menu?.items.contains { $0.action == #selector(MenuTarget.capture) } == true)
}
