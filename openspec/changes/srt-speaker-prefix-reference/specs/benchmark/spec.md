## MODIFIED Requirements

### Requirement: Parse SRT reference into ground truth

The benchmark SHALL parse a SubRip (`.srt`) reference file into an ordered list of cues (index, start, end, text) and derive the ground-truth reference text by concatenating cue texts in order. When cue texts carry speaker-label prefixes — a leading `<name>: ` (name up to 40 characters, containing no colon) whose exact name recurs on two or more cues — the reference-text derivation SHALL strip every prefix belonging to that recurring set, so speaker labels never count against the hypothesis; a colon-prefixed phrase that appears only once SHALL be preserved as-is (the heuristic cannot distinguish one-off body text from a speaker who spoke once; recurrence is the sole signal). Only the ASCII colon (`:`) delimits a prefix — fullwidth-colon labels are out of scope. Cue texts themselves stay verbatim (stripping happens at reference-text derivation only). A missing or unparseable reference file SHALL produce a clear error and a usage-error exit, before any transcription starts.

#### Scenario: Valid SRT yields reference text

- **WHEN** the reference file contains two cues with texts "hello" and "world"
- **THEN** parsing yields two cues in order
- **AND** the reference text is the ordered concatenation of "hello" and "world"

#### Scenario: Recurring speaker prefixes are stripped from the reference text

- **WHEN** the reference file's cues read `Kara Swisher: So, let's get started.`, `Steve Jobs: Sure.`, `Kara Swisher: Great.`, and `Steve Jobs: Thanks.`
- **THEN** the reference text is `So, let's get started. Sure. Great. Thanks.`
- **AND** each parsed cue's own text still carries its original prefix

#### Scenario: A one-off colon phrase is preserved as-is

- **WHEN** one cue's text reads `Note: the demo starts now` and no other cue starts with `Note: `
- **THEN** the reference text preserves `Note: the demo starts now` verbatim

#### Scenario: Malformed SRT is rejected before transcription

- **WHEN** the reference file lacks any valid `HH:MM:SS,mmm --> HH:MM:SS,mmm` timecode line
- **THEN** a clear parse error is raised naming the file
- **AND** no candidate transcription is started
