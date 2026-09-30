import FactoryCore
import Foundation
import Testing

@Test func customPromptOverridesFrozenUntilReset() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let frozen = try MySlopText.prompt.builtIn()
    #expect(try MySlopText.prompt.current(appDataFolder: folder) == frozen)
    let url = try MySlopText.prompt.editableURL(appDataFolder: folder)
    #expect(try String(contentsOf: url, encoding: .utf8) == frozen)
    try "Build a duck.".write(to: url, atomically: true, encoding: .utf8)
    #expect(try MySlopText.prompt.current(appDataFolder: folder) == "Build a duck.")
    try MySlopText.prompt.reset(appDataFolder: folder)
    #expect(try MySlopText.prompt.current(appDataFolder: folder) == frozen)
}

@Test func customPostTextKeepsPreviousPostAndRepository() throws {
    let repository = URL(string: "https://github.com/example/slop")!
    let text = FactoryCore.postText(
        model: "gpt-new", previousPost: "https://x.com/p/1", repositoryURL: repository,
        headline: "Look what {model} made.\n"
    )
    #expect(text == "Look what gpt-new made.\n\nPrevious post: https://x.com/p/1\n\nhttps://github.com/example/slop")
}
