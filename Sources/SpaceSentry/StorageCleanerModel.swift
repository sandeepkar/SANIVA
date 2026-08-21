import AppKit
import Foundation
@preconcurrency import UserNotifications
import UniformTypeIdentifiers
import SANIVACore

struct CleanupTarget: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case trash = "Trash"; case caches = "App caches" }
    let kind: Kind
    let url: URL
    var id: Kind { kind }
    var bytes: Int64 = 0
    var isSelected = true
    var detail: String
}

struct CleanupResult: Equatable, Sendable {
    let reclaimedBytes: Int64
    let availableBytes: Int64
    let skippedItems: Int
}

struct AppRemovalRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    let urls: [URL]
    let bytes: Int64
    var names: String { urls.map(\.lastPathComponent).joined(separator: ", ") }
}

@MainActor
final class StorageCleanerModel: ObservableObject {
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var availableBytes: Int64 = 0
    @Published private(set) var targets: [CleanupTarget] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var isScanningDuplicates = false
    @Published private(set) var isScanningAllUsers = false
    @Published private(set) var otherUsersSafeBytes: Int64?
    @Published var lastResult: CleanupResult?
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var duplicateProgress = DuplicateScanProgress(phase: .discovering, completed: 0, total: 0)
    @Published private(set) var duplicateExaminedFiles = 0
    @Published private(set) var duplicateInaccessibleFiles = 0
    @Published private(set) var duplicateElapsed: TimeInterval = 0
    @Published var appRemovalRequest: AppRemovalRequest?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var weeklyReminderEnabled = UserDefaults.standard.bool(forKey: "weeklyReminderEnabled") {
        didSet { updateWeeklyReminder() }
    }
    private var duplicateScanTask: Task<Void, Never>?

    var selectedBytes: Int64 { targets.filter(\.isSelected).reduce(0) { $0 + $1.bytes } }
    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var canClean: Bool { !isScanning && !isCleaning && targets.contains { $0.isSelected && $0.bytes > 0 } }

    func refresh() async {
        isScanning = true
        errorMessage = nil
        let choices = Dictionary(uniqueKeysWithValues: targets.map { ($0.kind, $0.isSelected) })
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations = [
            CleanupTarget(kind: .trash, url: home.appending(path: ".Trash", directoryHint: .isDirectory), detail: "Items you already put in the Trash"),
            CleanupTarget(kind: .caches, url: home.appending(path: "Library/Caches", directoryHint: .isDirectory), detail: "Temporary data created by your apps")
        ]
        let snapshot = await Task.detached(priority: .userInitiated) {
            let space = Self.volumeSpace()
            return (space.total, space.available, locations.map { item in
                var result = item; result.bytes = Self.allocatedSize(of: item.url); return result
            })
        }.value
        totalBytes = snapshot.0
        availableBytes = snapshot.1
        targets = snapshot.2.map { item in var result = item; result.isSelected = choices[item.kind] ?? true; return result }
        isScanning = false
    }

    func toggle(_ target: CleanupTarget) {
        guard let index = targets.firstIndex(where: { $0.id == target.id }) else { return }
        targets[index].isSelected.toggle()
    }

    func cleanSelected() async {
        let selected = targets.filter { $0.isSelected && $0.bytes > 0 }
        guard !selected.isEmpty else { return }
        isCleaning = true; errorMessage = nil; lastResult = nil
        lastResult = await Task.detached(priority: .userInitiated) {
            let before = Self.volumeSpace().available
            let skipped = selected.reduce(0) { $0 + Self.removeContents(of: $1.url) }
            let after = Self.volumeSpace().available
            return CleanupResult(reclaimedBytes: max(0, after - before), availableBytes: after, skippedItems: skipped)
        }.value
        isCleaning = false
        await refresh()
    }

    var duplicateSelectedBytes: Int64 { duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes } }
    var duplicateFileCount: Int { duplicateGroups.reduce(0) { $0 + $1.files.count } }

    func chooseAndScanDuplicates() {
        guard !isScanningDuplicates else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.folder, .data]
        panel.prompt = "Scan selection"
        panel.message = "Choose folders, or choose files to scan their containing folders"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        startDuplicateScan(roots: DuplicateScanner.normalizedRoots(from: panel.urls))
    }

    func startDuplicateScan(roots: [URL]) {
        duplicateScanTask?.cancel()
        isScanningDuplicates = true; errorMessage = nil; duplicateGroups = []
        duplicateProgress = .init(phase: .discovering, completed: 0, total: 0)
        statusMessage = "Scanning \(roots.count) selected folder(s)…"
        duplicateScanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .utility) {
                    try DuplicateScanner.scan(roots: roots) { progress in
                        Task { @MainActor [weak self] in self?.duplicateProgress = progress }
                    }
                }.value
                duplicateGroups = result.groups
                duplicateExaminedFiles = result.examinedFiles
                duplicateInaccessibleFiles = result.inaccessibleFiles
                duplicateElapsed = result.elapsed
                statusMessage = "Duplicate scan complete. No files were changed."
            } catch is CancellationError {
                statusMessage = "Duplicate scan cancelled. No files were changed."
            } catch {
                errorMessage = "Duplicate scan failed: \(error.localizedDescription)"
            }
            isScanningDuplicates = false
        }
    }

    func cancelDuplicateScan() { duplicateScanTask?.cancel() }

    func toggleDuplicate(groupID: String, fileID: URL) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }),
              let fileIndex = duplicateGroups[groupIndex].files.firstIndex(where: { $0.id == fileID }) else { return }
        let currentlySelected = duplicateGroups[groupIndex].files[fileIndex].isSelected
        if !currentlySelected && duplicateGroups[groupIndex].files.filter({ !$0.isSelected }).count <= 1 { return }
        duplicateGroups[groupIndex].files[fileIndex].isSelected.toggle()
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func moveSelectedDuplicatesToTrash() async {
        let selected = duplicateGroups.flatMap(\.files).filter(\.isSelected)
        guard !selected.isEmpty else { return }
        var failures = 0
        for file in selected {
            do { try FileManager.default.trashItem(at: file.url, resultingItemURL: nil) }
            catch { failures += 1 }
        }
        duplicateGroups = duplicateGroups.compactMap { group in
            var updated = group
            updated.files.removeAll { file in file.isSelected && !FileManager.default.fileExists(atPath: file.url.path) }
            return updated.files.count > 1 ? updated : nil
        }
        statusMessage = failures == 0 ? "Selected duplicates moved to Trash and can be restored." : "Some files could not be moved; \(failures) were left in place."
    }

    func scanAllUsers() async {
        guard !isScanningAllUsers else { return }
        isScanningAllUsers = true; errorMessage = nil
        do {
            otherUsersSafeBytes = try await Task.detached(priority: .userInitiated) { try Self.allUsersSafeSize() }.value
            statusMessage = "Administrator-approved scan complete. Other users’ files remain read-only."
        } catch {
            errorMessage = "The all-user scan was cancelled or could not finish. \(error.localizedDescription)"
        }
        isScanningAllUsers = false
    }

    func chooseApps() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = "Choose app bundles to review for removal"
        if panel.runModal() == .OK { prepareAppRemoval(panel.urls) }
    }

    func prepareAppRemoval(_ urls: [URL]) {
        let accepted = urls.map(\.standardizedFileURL).filter(Self.isRemovableApp)
        guard !accepted.isEmpty else {
            errorMessage = "Choose a non-system .app bundle. macOS system apps and Saniva Cleaner itself are protected."
            return
        }
        appRemovalRequest = AppRemovalRequest(urls: accepted, bytes: accepted.reduce(0) { $0 + Self.allocatedSize(of: $1) })
    }

    func removeRequestedApps() async {
        guard let request = appRemovalRequest else { return }
        appRemovalRequest = nil
        let result = await Task.detached(priority: .userInitiated) {
            let before = Self.volumeSpace().available
            var failures = 0
            for url in request.urls {
                guard Self.isRemovableApp(url) else { failures += 1; continue }
                do { try FileManager.default.removeItem(at: url) } catch { failures += 1 }
            }
            return (max(0, Self.volumeSpace().available - before), failures)
        }.value
        statusMessage = result.1 == 0
            ? "App removal complete. Freed \(Self.format(result.0)); personal data outside the bundle was untouched."
            : "Some selected apps were protected or in use and were left alone."
        await refresh()
    }

    private func updateWeeklyReminder() {
        UserDefaults.standard.set(weeklyReminderEnabled, forKey: "weeklyReminderEnabled")
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-space-review"])
        guard weeklyReminderEnabled else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else {
                Task { @MainActor in self?.weeklyReminderEnabled = false; self?.errorMessage = "Notifications are off, so the weekly reminder could not be enabled." }
                return
            }
            var date = DateComponents(); date.weekday = 2; date.hour = 10
            let content = UNMutableNotificationContent()
            content.title = "Time for a storage check"
            content.body = "Open Saniva Cleaner to review safe cleanup options. Nothing is removed automatically."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "weekly-space-review", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))) { error in
                if let error { Task { @MainActor in self?.errorMessage = error.localizedDescription } }
            }
        }
    }

    nonisolated private static func volumeSpace() -> (total: Int64, available: Int64) {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) else { return (0, 0) }
        return (Int64(values.volumeTotalCapacity ?? 0), values.volumeAvailableCapacityForImportantUsage.map { Int64($0) } ?? 0)
    }

    nonisolated private static func allocatedSize(of root: URL) -> Int64 {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return 0 }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else { return 0 }
        var bytes: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys), values.isSymbolicLink != true else { continue }
            if values.isRegularFile == true { bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0) }
        }
        return bytes
    }

    nonisolated private static func removeContents(of directory: URL) -> Int {
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return 0 }
        return children.reduce(0) { count, child in
            do { try FileManager.default.removeItem(at: child); return count } catch { return count + 1 }
        }
    }

    nonisolated private static func isRemovableApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        return url.pathExtension.lowercased() == "app"
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue && path != Bundle.main.bundleURL.standardizedFileURL.path
            && !path.hasPrefix("/System/")
    }

    nonisolated private static func allUsersSafeSize() throws -> Int64 {
        let script = "do shell script \"/usr/bin/du -sk /Users/*/.Trash /Users/*/Library/Caches 2>/dev/null || true\" with administrator privileges"
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); process.arguments = ["-e", script]
        process.standardOutput = pipe; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.userCancelled) }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: "\n").reduce(0) { total, line in
            total + (Int64(line.split(whereSeparator: \.isWhitespace).first ?? "") ?? 0) * 1_024
        }
    }

    nonisolated static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
