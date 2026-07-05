## MODIFIED Requirements

### Requirement: Compute accuracy metric selected by language

The benchmark SHALL compute an edit-distance-based error rate between the normalized hypothesis and the normalized reference: character error rate (CER) for languages written without word spacing (including `zh`, `ja`, `ko`), and word error rate (WER) with whitespace tokenization otherwise. The report SHALL name which metric kind was used. Normalization applied to both sides SHALL include Unicode NFKC, punctuation removal, fullwidth-to-halfwidth folding, lowercasing, and whitespace collapsing. For `zh`, normalization SHALL additionally fold Han script variants by converting BOTH sides Traditional→Simplified before comparison (the well-defined many-to-one direction), so CER measures recognition content rather than output script — Whisper-family models emit Simplified by default while this project's Chinese references are Traditional. The transcript files delivered to the user are NOT script-converted; the fold applies only inside metric computation. Languages other than `zh` (including `ja`, whose kanji must not be rewritten) SHALL NOT receive the script fold.

#### Scenario: Chinese audio uses CER

- **WHEN** the benchmark language is `zh`
- **THEN** the accuracy metric kind is `cer`

#### Scenario: English audio uses WER

- **WHEN** the benchmark language is `en`
- **THEN** the accuracy metric kind is `wer`

#### Scenario: Simplified output against a Traditional reference is not penalized

- **GIVEN** language `zh`, normalized reference "電話軟體" and normalized hypothesis "电话软体"
- **WHEN** CER is computed
- **THEN** both sides fold to the same Simplified text and CER = 0

#### Scenario: Japanese kanji are not script-folded

- **GIVEN** language `ja`, a reference containing 気 and a hypothesis containing 氣
- **WHEN** CER is computed
- **THEN** the characters are compared as-is (no Traditional→Simplified rewriting of Japanese text)

##### Example: CER on a five-character reference

- **GIVEN** normalized reference "今天天氣好" and normalized hypothesis "今天天很好"
- **WHEN** CER is computed
- **THEN** the edit distance is 1 substitution over 5 reference characters and CER = 0.2

##### Example: WER on a four-word reference

- **GIVEN** normalized reference "the cat sat down" and normalized hypothesis "the cat sat"
- **WHEN** WER is computed
- **THEN** the edit distance is 1 deletion over 4 reference words and WER = 0.25
