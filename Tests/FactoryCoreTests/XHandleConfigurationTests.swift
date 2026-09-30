import Foundation
import Testing
import FactoryCore

struct XHandleConfigurationTests {
    @Test func onlyExplicitHTTPSProjectDestinationsAreAccepted() {
        for url in ["", "http://example.supabase.co", "https://user:pass@example.supabase.co", "https://example.supabase.co/path", "https://example.supabase.co?token=secret", "https://example.supabase.co#part"] {
            #expect(XHandleRegistrationConfiguration(projectURL: url, publishableKey: "sb_publishable_test") == nil)
        }
    }

    @Test func onlyPublishableKeysWithoutHeaderInjectionAreAccepted() {
        for key in ["", "sb_secret_test", "service_role", "eyJhbGciOiJIUzI1NiJ9.legacy.signature", "sb_publishable_", "sb_publishable_a\nCookie: secret"] {
            #expect(XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: key) == nil)
        }
    }

    @Test func equivalentDestinationsAreCanonicalizedAndKeyIsPreserved() throws {
        for url in ["https://example.supabase.co", "https://EXAMPLE.SUPABASE.CO/", "https://example.supabase.co:443/"] {
            let configuration = try #require(XHandleRegistrationConfiguration(projectURL: url, publishableKey: "sb_publishable_test-123"))
            #expect(configuration.projectURL.absoluteString == "https://example.supabase.co")
            #expect(configuration.publishableKey == "sb_publishable_test-123")
        }
    }
}
