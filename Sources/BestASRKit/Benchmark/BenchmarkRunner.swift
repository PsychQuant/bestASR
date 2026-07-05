import Foundation

/// Injectable time/memory sources so the runner is deterministic under test
/// (design D7/D11). The live probe uses a continuous clock and the process
/// physical-footprint counters from libproc.
public struct MeasurementProbe: Sendable {
    /// Monotonic seconds.
    public var now: @Sendable () -> Double
    /// Approximate current process footprint in GB.
    public var memoryGB: @Sendable () -> Double

    public init(now: @escaping @Sendable () -> Double, memoryGB: @escaping @Sendable () -> Double) {
        self.now = now
        self.memoryGB = memoryGB
    }

    public static func live() -> MeasurementProbe {
        MeasurementProbe(
            now: {
                Double(DispatchTime.now().uptimeNanoseconds) / 1e9
            },
            memoryGB: {
                var info = rusage_info_current()
                let ok = withUnsafeMutablePointer(to: &info) { ptr in
                    ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
                    }
                }
                guard ok == 0 else { return 0 }
                return Double(info.ri_phys_footprint) / 1e9
            }
        )
    }
}

/// One successfully measured candidate: the persisted record plus run-only
/// context the report shows but the cache does not need.
public struct MeasuredCandidate: Sendable {
    public let record: BenchmarkRecord
    /// Warm-up wall-clock seconds (model download + first load) — reported
    /// separately, never part of RTF (design D7).
    public let warmupSeconds: Double
    /// Error rate of the with-context pass (spec benchmark: Measure the
    /// context-biasing delta); nil when no context directory was provided.
    /// Only the baseline record is ever persisted (design D6).
    public let contextErrorRate: Double?

    public init(record: BenchmarkRecord, warmupSeconds: Double, contextErrorRate: Double? = nil) {
        self.record = record
        self.warmupSeconds = warmupSeconds
        self.contextErrorRate = contextErrorRate
    }
}

public struct BenchmarkFailure: Sendable {
    public let candidate: BenchmarkCandidate
    public let reason: String
}

/// The full outcome of one benchmark run.
public struct BenchmarkOutcome: Sendable {
    public let measured: [MeasuredCandidate]
    public let failures: [BenchmarkFailure]
    public let notes: [String]
    public let metricKind: MetricKind
    public let language: String
}

/// Enumerates candidates and measures them one by one (spec benchmark).
public struct BenchmarkRunner {
    let engines: [any Engine]
    let host: SystemInfo
    let probe: MeasurementProbe

    public init(engines: [any Engine], host: SystemInfo, probe: MeasurementProbe = .live()) {
        self.engines = engines
        self.host = host
        self.probe = probe
    }

    // MARK: - Candidate enumeration (spec: Enumerate candidate configurations)

    public struct Enumeration: Sendable {
        public let candidates: [BenchmarkCandidate]
        public let notes: [String]
    }

    public func enumerateCandidates(
        backendFilter: [String]? = nil,
        modelFilter: [String]? = nil,
        allGrid: Bool = false
    ) async throws -> Enumeration {
        let backendNames = Set(BackendID.allCases.map(\.rawValue))
        if let backendFilter {
            for name in backendFilter where !backendNames.contains(name.lowercased()) {
                throw BestASRError.usage(
                    "unknown backend in filter: '\(name)'; supported backends are "
                        + backendNames.sorted().joined(separator: ", ")
                )
            }
        }
        // Valid model addresses come from the runnable backends' grid rows
        // (the mlx-audio reference catalog never enumerates, spec model-grid).
        let gridNames = Set(ModelGrid.rows
            .filter { $0.backend != ModelGrid.backendMLXAudio }
            .map(\.size))
        if let modelFilter {
            for name in modelFilter where !gridNames.contains(name.lowercased()) {
                throw BestASRError.usage(
                    "unknown model in filter: '\(name)'; run list-models for the catalog"
                )
            }
        }

        var candidates: [BenchmarkCandidate] = []
        var notes: [String] = []
        for engine in engines {
            let backend = engine.id
            if let backendFilter,
                !backendFilter.contains(where: { $0.lowercased() == backend.rawValue })
            {
                continue
            }
            guard await engine.isAvailable() else {
                notes.append("skipped \(backend.rawValue): backend unavailable on this machine")
                continue
            }
            // Runnable backends' rows are all priority 1; the mlx-audio
            // reference catalog never reaches here (engines drive the loop,
            // spec benchmark: Reference rows never enumerate).
            let ceiling: Int? = allGrid ? nil : 1
            for row in ModelGrid.rows(backend: backend.rawValue, priorityCeiling: ceiling) {
                if let modelFilter,
                    !modelFilter.contains(where: { $0.lowercased() == row.size })
                {
                    continue
                }
                candidates.append(
                    BenchmarkCandidate(
                        backend: backend, model: row.size, quantization: row.quantization))
            }
        }
        return Enumeration(candidates: candidates, notes: notes)
    }

    // MARK: - Measurement (spec: Measure speed and memory per candidate,
    //                      Warn-continue on per-candidate failure)

    public func run(
        candidates: [BenchmarkCandidate],
        notes initialNotes: [String],
        audio: AudioInfo,
        referenceText: String,
        metricKind: MetricKind,
        language: String,
        contextPrompt: String? = nil,
        deterministicDecode: Bool = false
    ) async -> BenchmarkOutcome {
        var measured: [MeasuredCandidate] = []
        var failures: [BenchmarkFailure] = []

        guard let audioDuration = audio.duration, audioDuration > 0 else {
            return BenchmarkOutcome(
                measured: [],
                failures: candidates.map {
                    BenchmarkFailure(
                        candidate: $0, reason: "audio duration unknown; cannot compute RTF")
                },
                notes: initialNotes,
                metricKind: metricKind,
                language: language
            )
        }

        for candidate in candidates {
            guard let engine = engines.first(where: { $0.id == candidate.backend }) else {
                failures.append(
                    BenchmarkFailure(candidate: candidate, reason: "no engine for backend"))
                continue
            }
            let effectiveLanguage = language == "auto" ? nil : language
            // Baseline options never carry the prompt — the persisted record
            // stays context-neutral (design D6).
            let options = TranscribeOptions(
                model: candidate.model,
                quantization: candidate.quantization,
                language: effectiveLanguage,
                deterministicDecode: deterministicDecode
            )
            do {
                // Memory baseline BEFORE warm-up: with pipeline reuse (#7) the
                // model is resident after warm-up, so a post-warm-up baseline
                // would collapse whisperkit peak-GB to decode-only ~0 and be
                // incomparable with pre-reuse records. Baseline-before-warm-up
                // keeps the candidate's model footprint in the delta
                // (subprocess backends still under-report — process-local probe).
                let memoryBefore = probe.memoryGB()

                // Warm-up run: downloads/loads the model; excluded from RTF.
                let warmStart = probe.now()
                _ = try await engine.transcribe(audioPath: audio.path, options: options)
                let warmupSeconds = probe.now() - warmStart

                // Timed run.
                let start = probe.now()
                let transcript = try await engine.transcribe(audioPath: audio.path, options: options)
                let elapsed = probe.now() - start
                let peakMemoryGB = max(probe.memoryGB() - memoryBefore, 0)

                let errorRate = ErrorRate.compute(
                    hypothesis: transcript.text, reference: referenceText, kind: metricKind,
                    language: language)

                // Optional second pass with the context prompt (spec benchmark:
                // Measure the context-biasing delta). Model is warm; failures
                // here degrade to a note-worthy nil, not a candidate failure.
                var contextErrorRate: Double?
                if let contextPrompt {
                    let contextOptions = TranscribeOptions(
                        model: candidate.model,
                        quantization: candidate.quantization,
                        language: effectiveLanguage,
                        prompt: contextPrompt,
                        deterministicDecode: deterministicDecode
                    )
                    if let contextTranscript = try? await engine.transcribe(
                        audioPath: audio.path, options: contextOptions)
                    {
                        contextErrorRate = ErrorRate.compute(
                            hypothesis: contextTranscript.text,
                            reference: referenceText, kind: metricKind, language: language)
                    }
                }
                let record = BenchmarkRecord(
                    backend: candidate.backend.rawValue,
                    model: candidate.model,
                    quantization: candidate.quantization,
                    language: language,
                    metricKind: metricKind,
                    errorRate: errorRate,
                    rtf: elapsed / audioDuration,
                    peakMemoryGB: (peakMemoryGB * 100).rounded() / 100,
                    audioDuration: audioDuration,
                    measuredAt: Date(),
                    chip: host.chip,
                    macosVersion: host.macosVersion,
                    appVersion: BestASRVersion.current
                )
                measured.append(
                    MeasuredCandidate(
                        record: record, warmupSeconds: warmupSeconds,
                        contextErrorRate: contextErrorRate))
            } catch {
                let reason = (error as? TranscriptionError)?.errorDescription
                    ?? error.localizedDescription
                failures.append(BenchmarkFailure(candidate: candidate, reason: reason))
            }
        }

        return BenchmarkOutcome(
            measured: measured,
            failures: failures,
            notes: initialNotes,
            metricKind: metricKind,
            language: language
        )
    }
}
