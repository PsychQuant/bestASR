import SwiftUI
import UniformTypeIdentifiers

import BestASRGUICore

/// Thin composer (swiftui-specialist structure rule): every section is its own
/// View struct with narrow inputs; this parent only wires state together.
struct ContentView: View {
    @State private var session = TranscribeSession(runner: GUITranscribe.coreRunner())
    @State private var audioURL: URL?
    @State private var showingImporter = false

    // Persisted defaults (spec gui-app: selections survive relaunch).
    @AppStorage("gui.language") private var language = "auto"
    @AppStorage("gui.effort") private var effort = "auto"
    @AppStorage("gui.format") private var format = "srt"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DropZoneSection(
                fileName: audioURL?.lastPathComponent,
                isRunning: session.isRunning,
                onChoose: { showingImporter = true }
            )
            OptionsBar(
                language: $language, effort: $effort, format: $format,
                disabled: session.isRunning)
            RunControls(
                canStart: audioURL != nil && !session.isRunning,
                isRunning: session.isRunning,
                onStart: start,
                onCancel: { session.cancel() })
            PhaseSection(phase: session.phase, onReset: { session.reset() })
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
        .fileImporter(
            isPresented: $showingImporter, allowedContentTypes: [.audio]
        ) { result in
            if case .success(let url) = result { audioURL = url }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !session.isRunning, let first = urls.first else { return false }
            audioURL = first
            return true
        }
    }

    private func start() {
        guard let url = audioURL else { return }
        session.start(
            TranscribeRequest(
                audioPath: url.path,
                requestedLanguage: GUIOptions.requestedLanguage(fromSelection: language),
                profileName: effort,
                formatName: format))
    }
}

/// Where the chosen file shows up; doubles as the drop target's visual.
struct DropZoneSection: View {
    let fileName: String?
    let isRunning: Bool
    let onChoose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(fileName ?? "Drop an audio file here")
                .font(.headline)
            Button("Choose File…", action: onChoose)
                .disabled(isRunning)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(.tertiary))
    }
}

/// Language / effort / format pickers. Vocabularies come from GUIOptions so
/// they track the core types.
struct OptionsBar: View {
    @Binding var language: String
    @Binding var effort: String
    @Binding var format: String
    let disabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            Picker("Language", selection: $language) {
                ForEach(GUIOptions.languages, id: \.self) { Text($0) }
            }
            Picker("Effort", selection: $effort) {
                ForEach(GUIOptions.efforts, id: \.self) { Text($0) }
            }
            Picker("Format", selection: $format) {
                ForEach(GUIOptions.formats, id: \.self) { Text($0) }
            }
        }
        .pickerStyle(.menu)
        .disabled(disabled)
    }
}

struct RunControls: View {
    let canStart: Bool
    let isRunning: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Button("Transcribe", action: onStart)
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
            if isRunning {
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
    }
}

/// Renders whichever phase the session is in. Split per state so a running
/// clock tick only invalidates the progress view.
struct PhaseSection: View {
    let phase: TranscribeSession.Phase
    let onReset: () -> Void

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .running(let startedAt):
            ProgressSection(startedAt: startedAt)
        case .done(let completion):
            ResultSection(completion: completion, onReset: onReset)
        case .failed(let message):
            FailureSection(message: message, onReset: onReset)
        }
    }
}

/// Stage + live elapsed clock (design D2 — honest indeterminate progress; the
/// engine exposes no percentage). TimelineView scopes the 1 Hz invalidation to
/// this view only.
struct ProgressSection: View {
    let startedAt: Date

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Transcribing…")
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(elapsedText(now: context.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func elapsedText(now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ResultSection: View {
    let completion: TranscribeSession.Completion
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(completion.outputPath, systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: completion.outputPath)])
                }
                Button("New Run", action: onReset)
            }
            Text(completion.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(completion.preview)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct FailureSection: View {
    let message: String
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Button("Start Over", action: onReset)
        }
    }
}
