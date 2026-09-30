import Foundation
import Testing
import FactoryCore

struct XHandleRegistrationTests {
    @Test func validHandlesAreNormalized() {
        #expect(XHandleValidation.normalize("Alice_1") == "alice_1")
        #expect(XHandleValidation.normalize("ALICE_1") == "alice_1")
        #expect(XHandleValidation.normalize("a") == "a")
        #expect(XHandleValidation.normalize("abcdefghijklmno") == "abcdefghijklmno")
    }

    @Test func invalidAndReservedHandlesAreRejected() {
        for handle in ["", "a/b", "@alice", "alice smith", "éclair", "abcdefghijklmnop", "HOME", "login", "connect_people", "who_to_follow"] {
            #expect(XHandleValidation.normalize(handle) == nil)
        }
    }

    @Test func onlyHTTPSXOriginsWithoutCredentialsAreTrusted() throws {
        for origin in ["https://x.com", "https://www.x.com/home", "https://X.COM:443/notifications"] {
            #expect(XHandleValidation.isTrustedOrigin(try #require(URL(string: origin))))
        }
        for origin in ["http://x.com", "https://x.com.evil.test", "https://twitter.com", "https://x.com:8443", "https://user:pass@x.com"] {
            #expect(!XHandleValidation.isTrustedOrigin(try #require(URL(string: origin))))
        }
    }
}
