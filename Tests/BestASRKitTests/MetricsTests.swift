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
    @Test func `zh CER folds Simplified output against a Traditional reference to zero`() {
        // #34 D7: Whisper emits Simplified for Mandarin; the reference is
        // Traditional. Both sides fold Hant→Hans before comparing, so CER
        // measures recognition content, not output script.
        // Note: this hypothesis is the exact character-fold of the reference —
        // it proves the fold MECHANIC. The fold is character-level only and
        // deliberately does NOT bridge lexical variants (软体 stays 软体, never
        // becomes mainland 软件); a real model emitting 软件 still scores a
        // substitution, which is honest — TW vocabulary is genuinely harder.
        #expect(
            ErrorRate.compute(
                hypothesis: "电话软体可达成发展结果", reference: "電話軟體可達成發展結果",
                kind: .cer, language: "zh") == 0)
    }

    @Test func `regional zh tags fold exactly like bare zh`() {
        // #34 verify HIGH: the fold gate shares LanguageResolver's base-subtag
        // predicate — zh-TW (this feature's signature locale) and zh-Hant must
        // hit the same fold path as "zh", or a zh-TW benchmark silently scores
        // script noise.
        for tag in ["zh-TW", "zh-tw", "zh-Hant", "zh-CN"] {
            #expect(
                ErrorRate.compute(
                    hypothesis: "电话软体可达成发展结果", reference: "電話軟體可達成發展結果",
                    kind: .cer, language: tag) == 0, "tag \(tag) must fold")
        }
    }

    @Test func `auto never folds even when CER was inferred from the reference`() {
        // `--language auto` reaches ErrorRate with the literal string "auto"
        // (metric kind inferred from the reference text). An unresolved
        // language cannot distinguish Chinese from Japanese, and ja kanji must
        // never be rewritten — so auto deliberately skips the fold. Users
        // wanting folded zh scoring pass an explicit zh tag.
        #expect(
            ErrorRate.compute(
                hypothesis: "电话", reference: "電話", kind: .cer, language: "auto") == 1.0)
    }

    @Test func `zh CER spec example is unchanged by the script fold`() {
        // Spec SBE: 今天天氣好 vs 今天天很好 → 1 substitution / 5 = 0.2 (both
        // sides fold consistently, so the genuine error survives).
        #expect(
            ErrorRate.compute(
                hypothesis: "今天天很好", reference: "今天天氣好", kind: .cer, language: "zh")
                == 0.2)
    }

    @Test func `ja kanji are not script-folded`() {
        // 氣 vs 気: distinct characters in Japanese; the zh-only fold must not
        // rewrite Japanese text (spec benchmark: Japanese kanji are not
        // script-folded).
        #expect(
            ErrorRate.compute(hypothesis: "氣", reference: "気", kind: .cer, language: "ja")
                == 1.0)
    }

    @Test func `nil language keeps the legacy behavior`() {
        #expect(
            ErrorRate.compute(hypothesis: "电话", reference: "電話", kind: .cer, language: nil)
                == 1.0)
    }

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
