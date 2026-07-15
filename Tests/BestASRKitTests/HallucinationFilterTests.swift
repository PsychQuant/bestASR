import Foundation
import Testing
@testable import BestASRKit

struct HallucinationFilterTests {
    /// Build a cue.
    private func seg(_ id: Int, _ text: String, start: Double = 0, end: Double = 1,
                     speaker: String? = nil) -> TranscriptSegment {
        TranscriptSegment(id: id, start: start, end: end, text: text, speaker: speaker)
    }

    /// Assemble a transcript, deriving `text` exactly the way an engine does
    /// (`segments.map(\.text).joined()` + trim), so the flat text going IN is
    /// realistic and we can assert the filter rebuilds it.
    private func make(_ segments: [TranscriptSegment]) -> Transcript {
        let text = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return Transcript(
            text: text, language: "zh", duration: segments.last?.end,
            backend: "whisperkit", model: "large-v3-turbo", segments: segments)
    }

    // (a) A known boilerplate cue is dropped, surviving cues are re-indexed
    // contiguously, and the flat text no longer contains the hallucination.
    @Test func `denylist drops boilerplate and reindexes`() {
        let input = make([
            seg(1, "大家好我們開始開會"),
            // The 2026-07-15 evidence string, with Whisper's spacing jitter.
            seg(2, "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目"),
            seg(3, "第一個議題是時間協調"),
        ])
        let out = HallucinationFilter.filter(input, mode: .denylist)
        #expect(out.segments.map(\.text) == ["大家好我們開始開會", "第一個議題是時間協調"])
        #expect(out.segments.map(\.id) == [1, 2])
        #expect(!out.text.contains("点赞"))
        #expect(out.text == "大家好我們開始開會第一個議題是時間協調")
    }

    // (b) A cue that merely shares words with a boilerplate phrase — but is not
    // the phrase — is kept. `訂閱` appears, but not the denylisted `請訂閱`.
    @Test func `look-alike legitimate speech is retained`() {
        let input = make([
            seg(1, "這個資料庫要訂閱才能看全文"),
            seg(2, "感謝各位今天來觀看我們的展覽"),
        ])
        let out = HallucinationFilter.filter(input, mode: .denylist)
        #expect(out.segments.count == 2)
        #expect(out.segments.map(\.text) == input.segments.map(\.text))
    }

    // (c) `.off` is an exact pass-through: same cues, ids, and flat text.
    @Test func `off mode passes through unchanged`() {
        let input = make([
            seg(1, "大家好"),
            seg(2, "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目"),
            seg(3, "結束"),
        ])
        let out = HallucinationFilter.filter(input, mode: .off)
        #expect(out.segments.map(\.text) == input.segments.map(\.text))
        #expect(out.segments.map(\.id) == input.segments.map(\.id))
        #expect(out.text == input.text)
    }

    // (d) Empty cues and adjacent exact-duplicate cues collapse.
    @Test func `empty and adjacent duplicate cues collapse`() {
        let input = make([
            seg(1, "開始"),
            seg(2, "   "),      // whitespace-only → empty → dropped
            seg(3, "重複的句子"),
            seg(4, "重複的句子"), // adjacent exact duplicate → dropped
            seg(5, "結束"),
        ])
        let out = HallucinationFilter.filter(input, mode: .denylist)
        #expect(out.segments.map(\.text) == ["開始", "重複的句子", "結束"])
        #expect(out.segments.map(\.id) == [1, 2, 3])
    }

    // (e) A clean transcript is returned untouched (ids + text byte-identical).
    @Test func `clean transcript is a no-op`() {
        let input = make([seg(1, "第一句"), seg(2, "第二句")])
        let out = HallucinationFilter.filter(input, mode: .denylist)
        #expect(out.segments.map(\.id) == input.segments.map(\.id))
        #expect(out.text == input.text)
    }

    // (f) Speaker labels on surviving cues are preserved through filtering.
    @Test func `speaker labels survive filtering`() {
        let input = make([
            seg(1, "主席發言", speaker: "SPEAKER_1"),
            seg(2, "感謝觀看", speaker: "SPEAKER_1"), // boilerplate → dropped
            seg(3, "委員回應", speaker: "SPEAKER_2"),
        ])
        let out = HallucinationFilter.filter(input, mode: .denylist)
        #expect(out.segments.map(\.text) == ["主席發言", "委員回應"])
        #expect(out.segments.map(\.speaker) == ["SPEAKER_1", "SPEAKER_2"])
    }
}
