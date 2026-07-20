import Foundation
import Testing
@testable import BestASRKit

// MARK: - 1.1 Schema (spec: Load and validate the context.json schema)

struct ContextSchemaTests {
    @Test func `Canonical v1 document loads with notes excluded from values`() throws {
        // Spec SBE: 2 terms, 1 name with 1 alias, 0 phrases, notes present.
        let json = """
            {
              "version": 1,
              "terms": ["benchmark-driven", "CoreML"],
              "names": [{ "name": "鄭澈", "aliases": ["Che"], "role": "主持人" }],
              "notes": "for the proofreading agent"
            }
            """
        let doc = try ContextDocument.load(data: Data(json.utf8), fileName: "context.json")
        #expect(doc.terms?.count == 2)
        #expect(doc.names?.count == 1)
        #expect(doc.names?[0].aliases == ["Che"])
        #expect(doc.names?[0].role == "主持人")
        #expect(doc.phrases == nil)
        // notes never reach rendering:
        let ctx = LoadedContext(directory: "x", document: doc, termListTerms: [], ignoredFiles: [])
        let rendered = PromptRenderer.render(ctx)
        #expect(!(rendered.prompt ?? "").contains("proofreading"))
    }

    @Test func `Unknown version is rejected naming the file and supported version`() {
        do {
            _ = try ContextDocument.load(data: Data(#"{"version": 99}"#.utf8), fileName: "ctx/context.json")
            Issue.record("expected a usage error")
        } catch let error as BestASRError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("99"))
            #expect(message.contains("1"))
            #expect(error.exitCode == 2)
        } catch { Issue.record("unexpected error type: \(error)") }
    }

    @Test func `Malformed JSON is rejected naming the file`() {
        #expect(throws: BestASRError.self) {
            _ = try ContextDocument.load(data: Data("not json".utf8), fileName: "context.json")
        }
    }
}

// MARK: - 1.2 Three-layer resolution (spec: Resolve the context directory by three-layer precedence)

struct ContextResolutionTests {
    @Test func `Explicit flag wins over both fallback layers`() throws {
        let cwd = try makeTempDir()
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: cwd); try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(
            at: cwd.appendingPathComponent(".bestasr/context"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".bestasr/context"), withIntermediateDirectories: true)
        let resolved = ContextLoader.resolveDirectory(flag: "/tmp/explicit-ctx", cwd: cwd, home: home)
        #expect(resolved?.path == "/tmp/explicit-ctx")
    }

    @Test func `Working-directory layer wins over the global layer`() throws {
        let cwd = try makeTempDir()
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: cwd); try? FileManager.default.removeItem(at: home) }
        let cwdCtx = cwd.appendingPathComponent(".bestasr/context")
        try FileManager.default.createDirectory(at: cwdCtx, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".bestasr/context"), withIntermediateDirectories: true)
        #expect(ContextLoader.resolveDirectory(flag: nil, cwd: cwd, home: home)?.path == cwdCtx.path)
    }

    @Test func `No layer present resolves to no context`() throws {
        let cwd = try makeTempDir()
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: cwd); try? FileManager.default.removeItem(at: home) }
        #expect(ContextLoader.resolveDirectory(flag: nil, cwd: cwd, home: home) == nil)
        #expect(try ContextLoader.load(flag: nil, cwd: cwd, home: home) == nil)
    }

    @Test func `Legacy cwd directory is no longer resolved`() throws {
        let cwd = try makeTempDir()
        let home = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: cwd); try? FileManager.default.removeItem(at: home) }
        // A legacy ./bestasr-context/ exists but the new ./.bestasr/context/ does not,
        // and there is no global layer — the legacy directory must not be resolved.
        try FileManager.default.createDirectory(
            at: cwd.appendingPathComponent("bestasr-context"), withIntermediateDirectories: true)
        #expect(ContextLoader.resolveDirectory(flag: nil, cwd: cwd, home: home) == nil)
        #expect(try ContextLoader.load(flag: nil, cwd: cwd, home: home) == nil)
    }

    @Test func `Flagged directory that does not exist is a usage error`() {
        #expect(throws: BestASRError.self) {
            _ = try ContextLoader.load(flag: "/nonexistent/ctx-dir")
        }
    }
}

// MARK: - 1.3 Folder ingest (spec: Merge plain-text term lists / Loudly ignore unsupported document formats)

struct ContextFolderTests {
    func fixtureDir() throws -> URL {
        let dir = try makeTempDir()
        try #"{"version":1,"terms":["alpha"]}"#.write(
            to: dir.appendingPathComponent("context.json"), atomically: true, encoding: .utf8)
        try "beta\n\n# comment line\ngamma\ndelta\n".write(
            to: dir.appendingPathComponent("terms.txt"), atomically: true, encoding: .utf8)
        try Data("fake pdf".utf8).write(to: dir.appendingPathComponent("lecture.pdf"))
        return dir
    }

    @Test func `txt terms join the pool after context terms and pdf is loudly ignored`() throws {
        let dir = try fixtureDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ctx = try ContextLoader.load(directory: dir)
        #expect(ctx.allTerms == ["alpha", "beta", "gamma", "delta"])  // json first, 3 txt lines after
        #expect(ctx.ignoredFiles == ["lecture.pdf"])
        // pdf content never affects the prompt
        let rendered = PromptRenderer.render(ctx)
        #expect(!(rendered.prompt ?? "").contains("fake"))
    }

    @Test func `Empty directory yields an empty context — zero impact`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ctx = try ContextLoader.load(directory: dir)
        #expect(ctx.isEmpty)
        #expect(PromptRenderer.render(ctx).prompt == nil)
    }
}

// MARK: - 1.4 Prompt rendering (spec: Render context into a natural-language prompt with priority and budget)

struct PromptRendererTests {
    @Test func `Worked example renders exactly as the spec SBE`() {
        let ctx = LoadedContext(
            directory: "x",
            document: ContextDocument(
                terms: ["benchmark-driven", "CoreML"],
                names: [.init(name: "鄭澈", aliases: ["Che"], role: "主持人")]
            ),
            termListTerms: [],
            ignoredFiles: []
        )
        let rendered = PromptRenderer.render(ctx)
        #expect(rendered.prompt == "鄭澈, Che, benchmark-driven, CoreML")
        #expect(rendered.truncated.isEmpty)
    }

    @Test func `Budget overflow drops phrases before terms before names and records them`() {
        let ctx = LoadedContext(
            directory: "x",
            document: ContextDocument(
                terms: ["term-one", "term-two"],
                names: [.init(name: "鄭澈", aliases: ["Che"])],
                phrases: ["a long phrase that should be dropped first"]
            ),
            termListTerms: [],
            ignoredFiles: []
        )
        // Budget fits names + first term only.
        let rendered = PromptRenderer.render(ctx, tokenBudget: 9)
        #expect(rendered.injected.contains("鄭澈"))
        #expect(rendered.injected.contains("Che"))
        #expect(!rendered.truncated.isEmpty)
        // Every phrase is truncated, and no phrase was injected while a term dropped.
        #expect(rendered.truncated.contains("a long phrase that should be dropped first"))
        #expect(!rendered.injected.contains("a long phrase that should be dropped first"))
    }

    @Test func `Cascade rule — once terms overflow, no phrase sneaks in`() {
        let ctx = LoadedContext(
            directory: "x",
            document: ContextDocument(
                terms: ["a very very long term exceeding budget entirely"],
                names: [],
                phrases: ["tiny"]
            ),
            termListTerms: [],
            ignoredFiles: []
        )
        let rendered = PromptRenderer.render(ctx, tokenBudget: 5)
        #expect(!rendered.injected.contains("tiny"))  // lower class dropped wholesale
        #expect(rendered.truncated.contains("tiny"))
    }

    @Test func `Duplicates are injected once`() {
        let ctx = LoadedContext(
            directory: "x",
            document: ContextDocument(terms: ["CoreML", "CoreML"]),
            termListTerms: ["CoreML"],
            ignoredFiles: []
        )
        let rendered = PromptRenderer.render(ctx)
        #expect(rendered.injected == ["CoreML"])
    }
}
