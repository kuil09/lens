import CoreGraphics

@MainActor
final class ScreenRecordingAccess {
    private let preflight: () -> Bool
    private let request: () -> Bool
    private(set) var requestedThisLaunch = false

    init(preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         request: @escaping () -> Bool = { CGRequestScreenCaptureAccess() }) {
        self.preflight = preflight
        self.request = request
    }

    var isGranted: Bool { preflight() }

    /// Only call from an explicit user action, never from capture restarts.
    func requestFromUserAction() -> Bool {
        if isGranted { return true }
        guard !requestedThisLaunch else { return false }
        requestedThisLaunch = true
        return request()
    }
}
