import CryptoKit
import Foundation

public struct DuplicateFile: Identifiable, Hashable, Sendable {
    public let url: URL
    public let bytes: Int64
    public let modifiedAt: Date?
    public var isSelected: Bool
    public var id: URL { url }
}

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let bytesPerFile: Int64
    public var files: [DuplicateFile]
    public var reclaimableBytes: Int64 { Int64(files.filter(\.isSelected).count) * bytesPerFile }
}

public struct DuplicateScanResult: Sendable {
    public let groups: [DuplicateGroup]
    public let examinedFiles: Int
    public let inaccessibleFiles: Int
    public let elapsed: TimeInterval
}

public struct DuplicateScanProgress: Sendable {
    public enum Phase: String, Sendable { case discovering = "Discovering files"; case sampling = "Comparing candidates"; case verifying = "Verifying exact matches" }
    public let phase: Phase
    public let completed: Int
    public let total: Int
    public init(phase: Phase, completed: Int, total: Int) { self.phase = phase; self.completed = completed; self.total = total }
}

public enum DuplicateScanner {
    public typealias ProgressHandler = @Sendable (DuplicateScanProgress) -> Void

    public static func scan(roots: [URL], progress: ProgressHandler = { _ in }) throws -> DuplicateScanResult {
        let started = Date()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var bySize: [Int64: [(URL, Date?)]] = [:]
        var examined = 0, inaccessible = 0

        for root in roots {
            try Task.checkCancellation()
            guard let items = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in inaccessible += 1; return true }
            ) else { inaccessible += 1; continue }
            for case let file as URL in items {
                try Task.checkCancellation()
                examined += 1
                if examined.isMultiple(of: 100) { progress(.init(phase: .discovering, completed: examined, total: 0)) }
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                      values.isSymbolicLink != true, let rawSize = values.fileSize else { continue }
                let size = Int64(rawSize)
                guard size > 0, size <= 20 * 1_024 * 1_024 * 1_024 else { continue }
                bySize[size, default: []].append((file, values.contentModificationDate))
            }
        }

        let candidates = bySize.values.filter { $0.count > 1 }.reduce(0) { $0 + $1.count }
        var sampled = 0
        var possible: [(Int64, [(URL, Date?)])] = []
        for (size, files) in bySize where files.count > 1 {
            var samples: [SHA256.Digest: [(URL, Date?)]] = [:]
            for file in files {
                try Task.checkCancellation(); sampled += 1
                if let digest = sampleDigest(of: file.0, size: size) { samples[digest, default: []].append(file) }
                if sampled.isMultiple(of: 25) { progress(.init(phase: .sampling, completed: sampled, total: candidates)) }
            }
            possible += samples.values.filter { $0.count > 1 }.map { (size, $0) }
        }

        let verificationTotal = possible.reduce(0) { $0 + $1.1.count }
        var verified = 0, groups: [DuplicateGroup] = []
        for (size, files) in possible {
            var hashes: [SHA256.Digest: [(URL, Date?)]] = [:]
            for file in files {
                try Task.checkCancellation(); verified += 1
                if let digest = fullDigest(of: file.0) { hashes[digest, default: []].append(file) } else { inaccessible += 1 }
                progress(.init(phase: .verifying, completed: verified, total: verificationTotal))
            }
            for (digest, matches) in hashes where matches.count > 1 {
                let sorted = matches.sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
                let duplicateFiles = sorted.enumerated().map { index, value in
                    DuplicateFile(url: value.0, bytes: size, modifiedAt: value.1, isSelected: index > 0)
                }
                groups.append(DuplicateGroup(id: digest.map { String(format: "%02x", $0) }.joined(), bytesPerFile: size, files: duplicateFiles))
            }
        }
        groups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return DuplicateScanResult(groups: groups, examinedFiles: examined, inaccessibleFiles: inaccessible, elapsed: Date().timeIntervalSince(started))
    }

    public static func normalizedRoots(from urls: [URL]) -> [URL] {
        Array(Set(urls.map { url in
            let standardized = url.standardizedFileURL
            let isDirectory = (try? standardized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory ? standardized : standardized.deletingLastPathComponent()
        })).sorted { $0.path < $1.path }
    }

    private static func sampleDigest(of url: URL, size: Int64) -> SHA256.Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: 65_536) else { return nil }
        hasher.update(data: head)
        if size > 65_536 {
            do { try handle.seek(toOffset: UInt64(max(0, size - 65_536))) } catch { return nil }
            guard let tail = try? handle.read(upToCount: 65_536) else { return nil }
            hasher.update(data: tail)
        }
        return hasher.finalize()
    }

    private static func fullDigest(of url: URL) -> SHA256.Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 1_048_576), !data.isEmpty {
            if Task.isCancelled { return nil }
            hasher.update(data: data)
        }
        return hasher.finalize()
    }
}
