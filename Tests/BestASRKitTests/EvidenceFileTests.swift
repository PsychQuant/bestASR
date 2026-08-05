import Foundation
import Testing

/// Internal-consistency contracts for the #122 evidence file.
///
/// Eight rounds of verification on `benchmarks/evidence/issue-122-fluidaudio-ab.json`
/// found no wrong value and a prose defect every round. Two of those classes are
/// mechanically checkable, and both have actually occurred:
///
/// - a field was renamed and a sentence elsewhere in the file kept naming the old
///   key, leaving one figure with no provenance and the sentence pointing at
///   nothing (round 8);
/// - a value was recorded whose method `path_coverage.how` never described, four
///   rounds running.
///
/// These tests turn both into build failures. They assert structure, never a
/// measured value — the values are checked by re-measuring them, not by asserting
/// them here, and pinning them in a test would only make the file harder to
/// correct.
struct EvidenceFileTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    private static func evidence() throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent(
            "benchmarks/evidence/issue-122-fluidaudio-ab.json")
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Field names the file's own prose mentions in backticks.
    ///
    /// Matched against the `path_coverage` value keys, so the pattern deliberately
    /// covers only the prefixes that block uses. A name that matches one of these
    /// prefixes but is not a key is a dangling reference.
    private static func backtickedFieldNames(in prose: String) -> Set<String> {
        let pattern =
            "`(case_folded_[a-z_]+|collapse_[a-z_]+|counterfactual_[a-z_]+|word_boundary_[a-z_]+)`"
        let re = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(prose.startIndex..., in: prose)
        return Set(
            re.matches(in: prose, range: range).compactMap {
                Range($0.range(at: 1), in: prose).map { String(prose[$0]) }
            })
    }

    /// Every `path_coverage` key the prose names in backticks must exist.
    ///
    /// Round 8: a rename to fix one finding broke another finding's fix in the same
    /// commit, because nothing cross-checked the two.
    @Test func `prose names no path_coverage field that does not exist`() throws {
        let d = try Self.evidence()
        let pc = try #require(d["path_coverage"] as? [String: Any])
        let how = try #require(pc["how"] as? [String: Any])

        var keys = Set(pc.keys)
        keys.remove("how")

        var prose = try #require(d["_reproducing"] as? String)
        for value in how.values {
            if let s = value as? String { prose += "\n" + s }
            if let a = value as? [String] { prose += "\n" + a.joined(separator: "\n") }
            if let m = value as? [String: String] {
                prose += "\n" + m.keys.joined(separator: "\n")
                prose += "\n" + m.values.joined(separator: "\n")
            }
        }
        if let limits = pc["_limits"] as? [String] { prose += "\n" + limits.joined(separator: "\n") }

        let dangling = Self.backtickedFieldNames(in: prose).subtracting(keys).sorted()
        #expect(
            dangling.isEmpty,
            """
            prose names path_coverage field(s) that do not exist: \(dangling).
            A rename has to reach every sentence that cites the old name — otherwise \
            the cited figure silently loses whatever the sentence said about it.
            """)
    }

    /// `path_coverage.how.probes` and the value keys must be in exact correspondence.
    ///
    /// A recorded value with no stated method is unreproducible; a stated method
    /// with no value is a method for something that is not here. Rounds 5-8 each
    /// found the first kind.
    @Test func `every recorded path_coverage value states how it was obtained`() throws {
        let d = try Self.evidence()
        let pc = try #require(d["path_coverage"] as? [String: Any])
        let how = try #require(pc["how"] as? [String: Any])
        let probes = try #require(how["probes"] as? [String: String])

        let values = Set(pc.keys.filter { $0 != "how" && !$0.hasPrefix("_") })
        let described = Set(probes.keys)

        #expect(
            values.subtracting(described).sorted().isEmpty,
            "recorded with no method in how.probes: \(values.subtracting(described).sorted())")
        #expect(
            described.subtracting(values).sorted().isEmpty,
            "how.probes describes absent field(s): \(described.subtracting(values).sorted())")
    }

    /// A method entry that is only a restatement of the field name tells a reader
    /// nothing. Each has to name where the number comes from, or say it is derived.
    @Test func `each probes entry says something beyond the field name`() throws {
        let d = try Self.evidence()
        let pc = try #require(d["path_coverage"] as? [String: Any])
        let how = try #require(pc["how"] as? [String: Any])
        let probes = try #require(how["probes"] as? [String: String])

        for (field, method) in probes {
            #expect(
                method.count >= 20,
                "how.probes[\(field)] is too short to state a method: \"\(method)\"")
        }
    }
}
