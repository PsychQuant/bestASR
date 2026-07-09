import Foundation
import Observation

import BestASRKit

/// One GUI transcription request (spec gui-app, #87). Value type so the view
/// layer can assemble it from pickers without touching core types.
public struct TranscribeRequest: Equatable, Sendable {
    public var audioPath: String
    /// nil = auto-detect (AudioProber decides).
    public var requestedLanguage: String?
    /// "auto" or a RouterProfile rawValue — resolved by CommandCore.
    public var profileName: String
    public var formatName: String
    /// nil lets the core derive the path next to the input.
    public var outputPath: String?

    public init(
        audioPath: String, requestedLanguage: String?, profileName: String,
        formatName: String, outputPath: String? = nil
    ) {
        self.audioPath = audioPath
        self.requestedLanguage = requestedLanguage
        self.profileName = profileName
        self.formatName = formatName
        self.outputPath = outputPath
    }
}

/// The seam between the GUI and the engine world (design D4): the app injects
/// CommandCore, tests inject a fake.
public typealias TranscribeRunner = @Sendable (TranscribeRequest) async throws -> TranscribeOutcome

/// GUI transcription state machine. Phase moves idle → running → done/failed;
/// `start` is single-flight and `cancel` returns to idle (the underlying engine
/// inference may keep running to completion — a documented v1 limitation, the
/// cancelled run's result is discarded via the generation guard).
@MainActor
@Observable
public final class TranscribeSession {
    public enum Phase: Equatable {
        case idle
        case running(startedAt: Date)
        case done(Completion)
        case failed(String)
    }

    /// What the result view renders (narrow, Equatable — swiftui-specialist).
    public struct Completion: Equatable, Sendable {
        public let outputPath: String
        public let formatName: String
        public let explanation: String
        public let preview: String

        public init(outputPath: String, formatName: String, explanation: String, preview: String) {
            self.outputPath = outputPath
            self.formatName = formatName
            self.explanation = explanation
            self.preview = preview
        }
    }

    public private(set) var phase: Phase = .idle

    private let runner: TranscribeRunner
    private let previewLimit: Int
    private var task: Task<Void, Never>?
    /// Bumped on every start/cancel so a stale in-flight completion (from a
    /// cancelled run) can never overwrite the current phase.
    private var generation = 0

    public init(runner: @escaping TranscribeRunner, previewLimit: Int = 20_000) {
        self.runner = runner
        self.previewLimit = previewLimit
    }

    public var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Single-flight: a start while running is a no-op (spec gui-app).
    public func start(_ request: TranscribeRequest) {
        guard !isRunning else { return }
        generation += 1
        let gen = generation
        phase = .running(startedAt: Date())
        let runner = self.runner
        let limit = previewLimit
        task = Task { [weak self] in
            do {
                let outcome = try await runner(request)
                let preview = await Self.loadPreview(path: outcome.outputPath, limit: limit)
                guard let self, self.generation == gen, self.isRunning else { return }
                self.phase = .done(
                    Completion(
                        outputPath: outcome.outputPath, formatName: outcome.format,
                        explanation: outcome.explanation, preview: preview))
            } catch {
                guard let self, self.generation == gen, self.isRunning else { return }
                if error is CancellationError {
                    self.phase = .idle
                } else {
                    self.phase = .failed(Self.message(for: error))
                }
            }
        }
    }

    /// Returns the UI to idle. The awaiting task is cancelled; if the engine
    /// does not observe cancellation its eventual result is dropped by the
    /// generation guard rather than resurrecting a stale phase.
    public func cancel() {
        guard isRunning else { return }
        generation += 1
        task?.cancel()
        task = nil
        phase = .idle
    }

    /// Clears a terminal phase so the user can start over.
    public func reset() {
        guard !isRunning else { return }
        phase = .idle
    }

    static func message(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription { return localized }
        return String(describing: error)
    }

    /// Off-main-thread read of the written transcript for the preview pane.
    nonisolated static func loadPreview(path: String, limit: Int) async -> String {
        await Task.detached(priority: .utility) {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return ""
            }
            guard content.count > limit else { return content }
            return String(content.prefix(limit)) + "\n…(preview truncated — full output on disk)"
        }.value
    }
}
