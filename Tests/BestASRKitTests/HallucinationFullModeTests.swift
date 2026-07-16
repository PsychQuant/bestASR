import Foundation
import Testing

@testable import BestASRKit

/// spec transcript-output (#100): the confidence-gated `full` filter mode.
/// Signals ride Whisper's canonical thresholds — the joint silence rule
/// (noSpeechProb > 0.6 AND avgLogprob < -1.0) and the repetition rule
/// (compressionRatio > 2.4). nil signals can never trip a rule, so backends
/// that don't populate them degrade to denylist behavior with no branching.
struct HallucinationFullModeTests {
    private func seg(
        _ id: Int, _ text: String, confidence: Double? = nil,
        noSpeech: Double? = nil, compression: Double? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id, start: Double(id), end: Double(id) + 1, text: text,
            confidence: confidence, noSpeechProb: noSpeech, compressionRatio: compression)
    }

    private func make(_ segments: [TranscriptSegment]) -> Transcript {
        let text = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return Transcript(
            text: text, language: "zh", duration: segments.last?.end,
            backend: "whisperkit", model: "large-v3-turbo", segments: segments)
    }

    // The joint silence rule needs BOTH signals past threshold (openai-whisper
    // semantics): high no-speech alone or low logprob alone must not drop —
    // that would eat quiet-but-real speech.
    @Test func `silence rule is a conjunction of noSpeech and logprob`() {
        let input = make([
            seg(1, "真的有人在說話", confidence: -0.2, noSpeech: 0.9),   // high ns, good lp → keep
            seg(2, "模糊但真實的話", confidence: -1.5, noSpeech: 0.3),   // low ns, bad lp → keep
            seg(3, "幻覺字幕", confidence: -1.5, noSpeech: 0.9),         // both → drop
            seg(4, "正常收尾"),
        ])
        let out = HallucinationFilter.filter(input, mode: .full)
        #expect(out.segments.map(\.text) == ["真的有人在說話", "模糊但真實的話", "正常收尾"])
    }

    @Test func `repetition rule drops above the compression threshold only`() {
        let input = make([
            seg(1, "重複重複重複重複重複重複", compression: 2.5),  // > 2.4 → drop
            seg(2, "臨界值上的正常句子", compression: 2.4),        // == threshold → keep
            seg(3, "一般句子", compression: 1.1),
        ])
        let out = HallucinationFilter.filter(input, mode: .full)
        #expect(out.segments.map(\.text) == ["臨界值上的正常句子", "一般句子"])
    }

    // Backends that never populate the signals (whisper.cpp / Parakeet) sail
    // through full mode untouched — full degrades to denylist for free.
    @Test func `nil signals never trip confidence rules`() {
        let input = make([
            seg(1, "無訊號後端的句子", confidence: -2.0),  // terrible logprob but no noSpeech signal
            seg(2, "另一句", confidence: nil),
        ])
        let out = HallucinationFilter.filter(input, mode: .full)
        #expect(out.segments.count == 2)
    }

    @Test func `full still applies the denylist and dedup passes`() {
        let input = make([
            seg(1, "感謝觀看"),                       // standalone boilerplate → dropped
            seg(2, "實際內容", noSpeech: 0.1),
            seg(3, "實際內容"),                       // adjacent duplicate → dropped
        ])
        let out = HallucinationFilter.filter(input, mode: .full)
        #expect(out.segments.map(\.text) == ["實際內容"])
    }

    // denylist mode must NOT gain confidence-gating (mode contract stays put).
    @Test func `denylist mode ignores confidence signals`() {
        let input = make([
            seg(1, "低信心但 denylist 模式", confidence: -3.0, noSpeech: 0.99, compression: 9.9)
        ])
        let out = HallucinationFilter.filter(input, mode: .denylist)
        #expect(out.segments.count == 1)
    }

    // The reindex path must forward the new fields — otherwise the signals die
    // mid-pipeline and downstream consumers (future) see nil.
    @Test func `reindex preserves confidence signals on survivors`() {
        let input = make([
            seg(1, "感謝觀看"),  // dropped → forces the reindex path
            seg(2, "留下的句子", confidence: -0.3, noSpeech: 0.2, compression: 1.7),
        ])
        let out = HallucinationFilter.filter(input, mode: .full)
        let survivor = out.segments[0]
        #expect(survivor.id == 1)
        #expect(survivor.noSpeechProb == 0.2)
        #expect(survivor.compressionRatio == 1.7)
        #expect(survivor.confidence == -0.3)
    }
}
