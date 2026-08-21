import Foundation

@main
enum DuplicateScannerChecks {
    static func main() throws {
        try findsExactCopies()
        try rejectsFalseMatches()
        try normalizesFileSelection()
        print("SANIVA duplicate scanner checks passed")
    }

    static func findsExactCopies() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("identical SANIVA test data".utf8)
        try data.write(to: root.appending(path: "a.txt")); try data.write(to: root.appending(path: "b.txt"))
        try Data("different".utf8).write(to: root.appending(path: "c.txt"))
        let result = try DuplicateScanner.scan(roots: [root])
        precondition(result.groups.count == 1)
        precondition(result.groups[0].files.count == 2)
        precondition(result.groups[0].files.filter(\.isSelected).count == 1)
        precondition(result.groups[0].reclaimableBytes == Int64(data.count))
    }

    static func rejectsFalseMatches() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("AAAA".utf8).write(to: root.appending(path: "a.txt")); try Data("BBBB".utf8).write(to: root.appending(path: "b.txt"))
        let result = try DuplicateScanner.scan(roots: [root])
        precondition(result.groups.isEmpty)
    }

    static func normalizesFileSelection() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "file.txt"); try Data().write(to: file)
        precondition(DuplicateScanner.normalizedRoots(from: [file]) == [root.standardizedFileURL])
    }

    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "SANIVA-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
}
