import Foundation
import Testing
@testable import BestASRKit

/// Plugin packaging contracts (spec plugin-marketplace).
struct PluginTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BestASRKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    @Test func `Plugin version tracks the app version`() throws {
        // Spec: releases bump plugin.json and BestASRVersion together — drift
        // turns the suite red (design D10).
        let manifestURL = Self.repoRoot
            .appendingPathComponent("plugins/bestasr/.claude-plugin/plugin.json")
        let data = try Data(contentsOf: manifestURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? String == BestASRVersion.current)
    }

    @Test func `Marketplace manifest lists the bestasr plugin`() throws {
        let manifestURL = Self.repoRoot
            .appendingPathComponent(".claude-plugin/marketplace.json")
        let data = try Data(contentsOf: manifestURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plugins = try #require(json["plugins"] as? [[String: Any]])
        #expect(plugins.contains { $0["name"] as? String == "bestasr" })
    }

    @Test func `Plugin packages exactly the two v1 skills`() {
        let skillsDir = Self.repoRoot.appendingPathComponent("plugins/bestasr/skills")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: skillsDir.path)) ?? []
        #expect(Set(entries) == Set(["context-ingest", "srt-proofread"]))
        for skill in entries {
            let skillFile = skillsDir.appendingPathComponent("\(skill)/SKILL.md")
            #expect(FileManager.default.fileExists(atPath: skillFile.path), "missing \(skill)/SKILL.md")
        }
    }
}
