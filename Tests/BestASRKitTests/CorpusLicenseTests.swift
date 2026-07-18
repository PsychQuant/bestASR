import Testing
@testable import BestASRKit

struct CorpusLicenseTests {
    @Test func `Allowed licenses parse`() {
        #expect(CorpusLicense.parse("CC0") == .cc0)
        #expect(CorpusLicense.parse(" CC-BY ") == .ccBy)   // trims whitespace
        #expect(CorpusLicense.parse("own-consented") == .ownConsented)
    }
    @Test func `Unknown licenses reject`() {
        #expect(CorpusLicense.parse("MIT") == nil)
        #expect(CorpusLicense.parse("") == nil)
        #expect(CorpusLicense.parse("all-rights-reserved") == nil)
    }
    @Test func `Allowed set is the five shareable licenses`() {
        #expect(CorpusLicense.allowed == ["CC0", "CC-BY", "CC-BY-SA", "public-domain", "own-consented"])
    }
}
