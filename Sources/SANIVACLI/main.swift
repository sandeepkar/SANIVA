import Foundation
import SANIVACore

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
    print("""
    SANIVA duplicate scanner 1.4

    Usage: saniva-scan [--json] PATH [PATH ...]

    Scans the chosen folders for exact duplicate files. This command is read-only:
    it reports matches and never moves or deletes files.
    """)
    exit(arguments.isEmpty ? 1 : 0)
}

let json = arguments.contains("--json")
let paths = arguments.filter { $0 != "--json" }.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
let roots = DuplicateScanner.normalizedRoots(from: paths)
guard !roots.isEmpty else { fputs("No valid scan paths supplied.\n", stderr); exit(2) }

do {
    let result = try DuplicateScanner.scan(roots: roots) { progress in
        guard !json else { return }
        let total = progress.total > 0 ? "/\(progress.total)" : ""
        fputs("\r\(progress.phase.rawValue): \(progress.completed)\(total)", stderr)
    }
    if json {
        let groups = result.groups.map { group in
            ["bytesPerFile": group.bytesPerFile, "files": group.files.map { $0.url.path }] as [String: Any]
        }
        let object: [String: Any] = ["groups": groups, "examinedFiles": result.examinedFiles, "inaccessibleFiles": result.inaccessibleFiles, "elapsedSeconds": result.elapsed]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        fputs("\r", stderr)
        print("Examined \(result.examinedFiles) files in \(String(format: "%.2f", result.elapsed)) seconds.")
        print("Found \(result.groups.count) duplicate set(s). \(result.inaccessibleFiles) item(s) were inaccessible.\n")
        for (index, group) in result.groups.enumerated() {
            print("Set \(index + 1) — \(ByteCountFormatter.string(fromByteCount: group.bytesPerFile, countStyle: .file)) each")
            group.files.forEach { print("  \($0.url.path)") }
        }
        print("\nRead-only scan complete. No files were changed.")
    }
} catch {
    fputs("Scan failed: \(error.localizedDescription)\n", stderr)
    exit(3)
}
