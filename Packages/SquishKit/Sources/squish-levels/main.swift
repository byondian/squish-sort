import Foundation
import SquishLevels

// squish-levels check <Levels dir>       Validate and re-solve every level (CI gate 2).
// squish-levels solve <file.json>        Print par and solution for one level.

let args = CommandLine.arguments
func usage() -> Never {
    print("usage: squish-levels check <Levels dir> | solve <level.json>")
    exit(2)
}
guard args.count >= 3 else { usage() }

switch args[1] {
case "check":
    let root = URL(fileURLWithPath: args[2], isDirectory: true)
    let files: [LevelFile]
    do { files = try LevelCatalog.loadFiles(root: root) } catch { print("❌ \(error)"); exit(1) }
    var failures = 0
    for file in files {
        let started = Date()
        let (problems, result) = LevelValidator.check(file)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if problems.isEmpty {
            print("✅ \(file.id) par \(result?.moves.count ?? 0) (\(result?.statesExplored ?? 0) states, \(ms) ms)")
        } else {
            failures += 1
            problems.forEach { print("❌ \($0)") }
        }
    }
    print("\(files.count) levels, \(failures) with problems")
    exit(failures == 0 && !files.isEmpty ? 0 : 1)
case "solve":
    do {
        let file = try LevelFile.decode(Data(contentsOf: URL(fileURLWithPath: args[2])))
        let level = try Level(file: file)
        guard let r = Solver.solve(level.board) else { print("no solution"); exit(1) }
        print("\"par\": \(r.moves.count),")
        print("\"solution\": [\(r.moves.map { "[\($0.from), \($0.to)]" }.joined(separator: ", "))],")
    } catch {
        print("❌ \(error)")
        exit(1)
    }
default:
    usage()
}
