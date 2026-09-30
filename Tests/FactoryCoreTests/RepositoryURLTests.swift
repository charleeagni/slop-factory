import Foundation
import Testing
@testable import FactoryCore

struct RepositoryURLTests {
    @Test func freshInstallCanDraftWithoutRepositorySetup() {
        let repository = FactoryCore.repositoryURL(bundled: nil, localOverride: nil)
        #expect(FactoryCore.postText(model: "gpt-new", previousPost: nil, repositoryURL: repository)
            .hasSuffix("\n\nhttps://github.com/charleeagni/slop-factory"))
    }

    @Test func invalidConfigurationFallsBackToProjectRepository() {
        let repository = FactoryCore.repositoryURL(bundled: "not a URL", localOverride: "file:///tmp/repo")
        #expect(repository.absoluteString == "https://github.com/charleeagni/slop-factory")
    }

    @Test func releaseDraftLinksToBundledRepositoryEvenWithLocalOverride() {
        let repository = FactoryCore.repositoryURL(
            bundled: "https://github.com/example/slop-factory",
            localOverride: "https://github.com/example/other-repository"
        )

        #expect(repository.absoluteString == "https://github.com/example/slop-factory")
        #expect(FactoryCore.postText(model: "gpt-new", previousPost: nil, repositoryURL: repository)
            .hasSuffix("\n\nhttps://github.com/example/slop-factory"))
    }

    @Test func localBuildCanUseConfiguredRepository() {
        let repository = FactoryCore.repositoryURL(
            bundled: nil,
            localOverride: "https://github.com/example/slop-factory"
        )

        #expect(repository.absoluteString == "https://github.com/example/slop-factory")
    }
}
