import Foundation

@MainActor
enum BenchmarkCommand {
    static func run(arguments: [String]) async {
        let engine = AppleTranslationEngine()
        for pair in TranslationBenchmark.directions {
            let state = await engine.availability(source: pair.source, target: pair.target)
            guard state == .installed else {
                print("BENCHMARK_BLOCKED: \(pair.source.rawValue)->\(pair.target.rawValue) \(state). Download translation languages in macOS System Settings, then retry.")
                return
            }
        }
        var records: [[String: Any]] = []
        for pair in TranslationBenchmark.directions {
            for sentence in TranslationBenchmark.corpus {
                let text = sentence.text(in: pair.source)
                let input = TranslationInput(id: UUID(), text: text, source: pair.source, target: pair.target)
                let started = ProcessInfo.processInfo.systemUptime
                do {
                    let result = try await engine.translate([input])
                    let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
                    records.append(["number": sentence.number, "source": pair.source.rawValue, "target": pair.target.rawValue,
                                    "input": text, "reference": sentence.text(in: pair.target), "output": result.first?.text ?? "",
                                    "milliseconds": elapsed, "coldDirection": sentence.number == 1])
                } catch {
                    records.append(["number": sentence.number, "source": pair.source.rawValue, "target": pair.target.rawValue, "error": error.localizedDescription])
                }
            }
            print("BENCHMARK_DIRECTION \(pair.source.rawValue)->\(pair.target.rawValue) complete")
        }
        guard let i = arguments.firstIndex(of: "--benchmark"), arguments.indices.contains(i + 1) else {
            print("Provide output JSON path after --benchmark."); return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["records": records, "hardware": "Run on current host; confirm separately", "kind": "synthetic text-only translation; excludes OCR/display"], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: arguments[i + 1]), options: .atomic)
            print("BENCHMARK_SAVED \(records.count) records")
        } catch { print("BENCHMARK_SAVE_ERROR \(error.localizedDescription)") }
    }
}
