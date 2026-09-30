import Foundation

enum ModelDetection {
    struct Observations {
        var modelsBySource: [String: Set<String>] = [:]
        var successfulSources: Set<String> = []
        var failedSources: Set<String> = []
        var successfulModels: Set<String> { modelsBySource.values.reduce(into: Set<String>()) { $0.formUnion($1) } }
    }

    static func observations(commandRunner: any CommandRunner, homeFolder: URL, appDataFolder: URL, providers: Set<ModelProvider>) -> Observations {
        var result = Observations()
        if providers.contains(.openAI) {
            if let models = codexModels(homeFolder: homeFolder) {
                result.successfulSources.insert("openai")
                result.modelsBySource["openai"] = models
            } else { result.failedSources.insert("openai") }
        }
        if providers.contains(.claude) {
            let configURL = homeFolder.appendingPathComponent(".claude.json")
            if !FileManager.default.fileExists(atPath: configURL.path) {
                result.failedSources.insert("claude-config")
            } else if let data = try? Data(contentsOf: configURL), let config = try? JSONDecoder().decode(ClaudeConfig.self, from: data) {
                result.successfulSources.insert("claude-config")
                result.modelsBySource["claude-config"] = Set((config.additionalModelOptionsCache ?? []).map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else { result.failedSources.insert("claude-config") }
            if let cli = cliPaths(commandRunner: commandRunner, homeFolder: homeFolder, appDataFolder: appDataFolder).claude {
                for alias in ["opus", "sonnet", "haiku"] {
                    let key = "claude-\(alias)"
                    if let model = claudeAliasModel(commandRunner: commandRunner, cli: cli, alias: alias, homeFolder: homeFolder, appDataFolder: appDataFolder) {
                        result.successfulSources.insert(key)
                        result.modelsBySource[key] = [model]
                    } else { result.failedSources.insert(key) }
                }
            }
        }
        return result
    }

    static func discoverProviders(
        commandRunner: any CommandRunner,
        homeFolder: URL,
        appDataFolder: URL
    ) -> Set<ModelProvider> {
        let paths = cliPaths(commandRunner: commandRunner, homeFolder: homeFolder, appDataFolder: appDataFolder)
        var providers: Set<ModelProvider> = []
        if paths.claude != nil { providers.insert(.claude) }
        if paths.codex != nil { providers.insert(.openAI) }
        return providers
    }

    static func savedExecutable(for model: String, appDataFolder: URL, commandRunner: any CommandRunner) -> URL? {
        let url = appDataFolder.appendingPathComponent("cli-paths.json")
        guard let data = try? Data(contentsOf: url),
              let paths = try? JSONDecoder().decode(CLIPaths.self, from: data),
              let path = model.hasPrefix("claude-") ? paths.claude : paths.codex
        else { return nil }
        if model.hasPrefix("claude-") { return URL(fileURLWithPath: path) }
        return newestCodexExecutable(savedPath: path, searchPath: paths.path, commandRunner: commandRunner)
    }

    static func codexModels(homeFolder: URL) -> Set<String>? {
        let cacheURL = homeFolder.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(DetectedCodexCache.self, from: data)
        else { return nil }
        return Set(cache.models.compactMap { model in
            model.visibility == "list" && !model.slug.isEmpty ? model.slug : nil
        })
    }

    private static func claudeAliasModel(commandRunner: any CommandRunner, cli: String, alias: String, homeFolder: URL, appDataFolder: URL) -> String? {
        var environment = runtimeEnvironment(appDataFolder: appDataFolder)
        environment["CLAUDE_CODE_EFFORT_LEVEL"] = "medium"
        guard let result = try? commandRunner.run(executable: URL(fileURLWithPath: cli), arguments: ["-p", "ok", "--model", alias, "--effort", "medium", "--output-format", "json"], workingFolder: homeFolder, timeout: 30, environment: environment), result.exitCode == 0, !result.timedOut,
              let data = result.stdout.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        let events: [ClaudeEvent]
        if let decoded = try? decoder.decode([ClaudeEvent].self, from: data) {
            events = decoded
        } else if let decoded = try? decoder.decode(ClaudeEvent.self, from: data) {
            events = [decoded]
        } else {
            return nil
        }
        guard let event = events.last(where: { $0.type == "result" }), event.isError == false,
              let modelUsage = event.modelUsage, modelUsage.count == 1,
              let model = modelUsage.keys.first, !model.isEmpty else { return nil }
        return model
    }

    private static func cliPaths(
        commandRunner: any CommandRunner,
        homeFolder: URL,
        appDataFolder: URL
    ) -> CLIPaths {
        let url = appDataFolder.appendingPathComponent("cli-paths.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(CLIPaths.self, from: data),
           saved.claude != nil || saved.codex != nil {
            if saved.path != nil { return saved }
            return discoverPaths(commandRunner: commandRunner, homeFolder: homeFolder, appDataFolder: appDataFolder)
        }
        return discoverPaths(commandRunner: commandRunner, homeFolder: homeFolder, appDataFolder: appDataFolder)
    }

    private static func discoverPaths(commandRunner: any CommandRunner, homeFolder: URL, appDataFolder: URL) -> CLIPaths {
        let script = "printf 'claude=%s\\ncodex=%s\\npath=%s\\n' \"$(command -v claude)\" \"$(command -v codex)\" \"$PATH\""
        guard let result = try? commandRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", script], workingFolder: homeFolder, timeout: 10
        ), result.exitCode == 0, !result.timedOut else { return CLIPaths(claude: nil, codex: nil, path: nil) }

        let lines = result.stdout.split(separator: "\n")
        let values = Dictionary(uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        let paths = CLIPaths(
            claude: executablePath(values["claude"]),
            codex: executablePath(values["codex"]),
            path: values["path"] ?? ProcessInfo.processInfo.environment["PATH"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(paths),
           (try? FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)) != nil {
            try? data.write(to: appDataFolder.appendingPathComponent("cli-paths.json"), options: .atomic)
        }
        return paths
    }

    static func runtimeEnvironment(appDataFolder: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: appDataFolder.appendingPathComponent("cli-paths.json")),
              let paths = try? JSONDecoder().decode(CLIPaths.self, from: data), let path = paths.path else { return [:] }
        return ["PATH": path]
    }
    private static func executablePath(_ value: String?) -> String? {
        guard let value, value.hasPrefix("/") else { return nil }
        return value
    }
}

private struct DetectedCodexCache: Decodable {
    let models: [DetectedCodexModel]
}

private struct DetectedCodexModel: Decodable {
    let slug: String
    let visibility: String
}

private struct ClaudeEvent: Decodable {
    let type: String
    let isError: Bool?
    let modelUsage: [String: TokenUsage]?

    enum CodingKeys: String, CodingKey {
        case type, modelUsage
        case isError = "is_error"
    }
}

private struct TokenUsage: Decodable {}

private struct ClaudeConfig: Decodable {
    let additionalModelOptionsCache: [ClaudeOption]?
}

private struct ClaudeOption: Decodable {
    let value: String
}

private struct CLIPaths: Codable {
    let claude: String?
    let codex: String?
    let path: String?
}
