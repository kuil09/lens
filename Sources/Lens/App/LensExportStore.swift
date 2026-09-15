import Foundation
import Combine
import Darwin

/// The non-sandboxed app retains a file bookmark, not an export history.
@MainActor final class LensExportStore: ObservableObject {
    @Published private(set) var directory: URL
    @Published private(set) var lastSavedURL: URL?
    private let defaults: UserDefaults
    private let defaultDirectory: URL
    private var resolutionFailed = false
    private static let bookmarkKey = "exportDirectoryBookmark"
    private static let pathKey = "exportDirectoryPath"

    init(defaults: UserDefaults = .standard, defaultDirectory: URL? = nil) {
        self.defaults = defaults
        let fallback = defaultDirectory ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lens", isDirectory: true)
        self.defaultDirectory = fallback
        directory = fallback
        if let bookmark = defaults.data(forKey: Self.bookmarkKey) {
            do {
                var stale = false
                directory = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                    relativeTo: nil, bookmarkDataIsStale: &stale)
                if stale, let refreshed = try? directory.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    defaults.set(refreshed, forKey: Self.bookmarkKey)
                    defaults.set(directory.path, forKey: Self.pathKey)
                }
            } catch {
                resolutionFailed = true
                if let path = defaults.string(forKey: Self.pathKey) { directory = URL(fileURLWithPath: path, isDirectory: true) }
            }
        }
    }

    func selectDirectory(_ url: URL) throws {
        try validateDirectory(url)
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(url.path, forKey: Self.pathKey)
        directory = url
        resolutionFailed = false
    }

    func preparedDirectory() throws -> URL {
        guard !resolutionFailed else { throw ExportError.directoryUnavailable }
        if defaults.data(forKey: Self.bookmarkKey) == nil, directory == defaultDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try validateDirectory(directory)
        return directory
    }

    func videoDestination(at date: Date = Date()) throws -> URL {
        try preparedDirectory().appendingPathComponent(filename(kind: "Video", date: date, extension: "mp4"))
    }

    @discardableResult func saveImage(_ data: Data, at date: Date = Date()) throws -> URL {
        let folder = try preparedDirectory()
        let temporary = folder.appendingPathComponent(".Lens-image-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        let destination = folder.appendingPathComponent(filename(kind: "Image", date: date, extension: "png"))
        let saved = try LensExportFiles.publish(temporary, to: destination)
        didSave(saved)
        return saved
    }

    func didSave(_ url: URL) { lastSavedURL = url }

    private func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: url.path) else { throw ExportError.directoryUnavailable }
    }

    private func filename(kind: String, date: Date, extension suffix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return "Lens-\(kind)-\(formatter.string(from: date)).\(suffix)"
    }
}

enum LensExportFiles {
    /// Both files live in the same directory. Exclusive rename also protects against
    /// another app creating the destination between the name check and publication.
    static func publish(_ temporary: URL, to proposed: URL) throws -> URL {
        for suffix in 1...10_000 {
            let destination = suffix == 1 ? proposed : proposed.deletingLastPathComponent()
                .appendingPathComponent("\(proposed.deletingPathExtension().lastPathComponent)-\(suffix).\(proposed.pathExtension)")
            let result = temporary.withUnsafeFileSystemRepresentation { source in
                destination.withUnsafeFileSystemRepresentation { target in
                    renamex_np(source!, target!, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return destination }
            let failure = errno
            if failure != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
        }
        throw ExportError.nameExhausted
    }
}

enum ExportError: LocalizedError {
    case directoryUnavailable, nameExhausted
    var errorDescription: String? {
        switch self {
        case .directoryUnavailable: L10n.text("Cannot access the save folder. Check the drive connection and write access, or choose a folder again in Settings → Capture.")
        case .nameExhausted: L10n.text("Too many files have the same name. Try again shortly or choose a different folder.")
        }
    }
}
