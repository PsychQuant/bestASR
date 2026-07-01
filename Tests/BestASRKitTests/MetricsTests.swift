import Foundation
import Testing
@testable import BestASRKit

struct SRTParserTests {
    @Test func `Valid SRT yields ordered cues and space-joined reference text`() throws {
        // Spec SBE: two cues "hello" and "world".
        let srt = """
            1
            00:00:00,000 --> 00:00:01,000
            hello

            2
            00:00:01,000 --> 00:00:02,500
            world
            """
        let cues = try SRTParser.parse(srt)
        #expect(cues.count == 2)
        #expect(cues[0].text == "hello")
        #expect(cues[1].text == "world")
        #expect(cues[0].start == 0.0)
        #expect(cues[1].end == 2.5)
        #expect(SRTParser.referenceText(from: cues) == "hello world")
    }

    @Test func `Multi-line cue text joins with a space`() throws {
        let srt = """
            1
            00:00:00,000 --> 00:00:02,000
            first line
            second line
            """
        let cues = try SRTParser.parse(srt)
        #expect(cues[0].text == "first line second line")
    }

    @Test func `Malformed SRT without any timecode is rejected`() {
        #expect(throws: BestASRError.self) {
            _ = try SRTParser.parse("just some text\nwith no timecodes at all")
        }
    }

    @Test func `Missing reference file is a usage error`() {
        #expect(throws: BestASRError.self) {
            _ = try SRTParser.parse(fileAt: "/nonexistent/reference.srt")
        }
    }

    @Test func `Dot millisecond separator is tolerated`() throws {
        let cues = try SRTParser.parse("1\n00:00:00.000 --> 00:00:01.500\nhi")
        #expect(cues[0].end == 1.5)
    }
}

struct TextNormalizerTests {
    @Test func `Normalization strips punctuation, folds width, lowercases, collapses whitespace`() {
        #expect(TextNormalizer.normalize("Hello,  WORLD!") == "hello world")
        // NFKC folds fullwidth Ｈｅｌｌｏ and ！
        #expect(TextNormalizer.normalize("Ｈｅｌｌｏ！") == "hello")
        #expect(TextNormalizer.normalize("今天，天氣好。") == "今天天氣好")
    }

    @Test func `CJK text passes through unharmed`() {
        #expect(TextNormalizer.normalize("今天天氣好") == "今天天氣好")
    }
}

struct ErrorRateTests {
    @Test func `CER on the five-character spec example is exactly 0,2`() {
        // Spec SBE: 「今天天氣好」 vs 「今天天很好」 → 1 substitution / 5 chars.
        let cer = ErrorRate.cer(hypothesis: "今天天很好", reference: "今天天氣好")
        #expect(abs(cer - 0.2) < 1e-9)
    }

    @Test func `WER on the four-word spec example is exactly 0,25`() {
        // Spec SBE: "the cat sat down" vs "the cat sat" → 1 deletion / 4 words.
        let wer = ErrorRate.wer(hypothesis: "the cat sat", reference: "the cat sat down")
        #expect(abs(wer - 0.25) < 1e-9)
    }

    @Test func `Identical strings score zero for both metrics`() {
        #expect(ErrorRate.cer(hypothesis: "今天天氣好", reference: "今天天氣好") == 0)
        #expect(ErrorRate.wer(hypothesis: "the cat", reference: "the cat") == 0)
    }

    @Test func `Punctuation and width noise do not inflate the error rate`() {
        let cer = ErrorRate.cer(hypothesis: "今天，天氣好。", reference: "今天天氣好")
        #expect(cer == 0)
        let wer = ErrorRate.wer(hypothesis: "The CAT, sat down!", reference: "the cat sat down")
        #expect(wer == 0)
    }

    @Test func `Empty reference with non-empty hypothesis caps at 1`() {
        #expect(ErrorRate.cer(hypothesis: "hi", reference: "") == 1)
        #expect(ErrorRate.cer(hypothesis: "", reference: "") == 0)
    }

    @Test func `Dispatcher selects the metric by kind`() {
        let byCer = ErrorRate.compute(hypothesis: "今天天很好", reference: "今天天氣好", kind: .cer)
        let byWer = ErrorRate.compute(hypothesis: "the cat sat", reference: "the cat sat down", kind: .wer)
        #expect(abs(byCer - 0.2) < 1e-9)
        #expect(abs(byWer - 0.25) < 1e-9)
    }
}
