## Context

FluidAudio：`Speaker(id:name:currentEmbedding:)`、`speakerManager.initializeKnownSpeakers(_:mode:)`、`performCompleteDiarization` 對已知者回其 id（distance < speakerThreshold 0.65）、`result.speakerDatabase: [String:[Float]]`。#25 已有：`DiarizationEngine`、`SpeakerAssigner`、CommandCore `diarizer:` 注入縫、pinned 2-speaker fixture。Context 模組已解析三層 context dir。

## Goals / Non-Goals

Goals：註冊名直出標籤、未知者不退化、隱私鐵律成文、可重現驗證。Non-goals 見 proposal。

## Decisions

### D1 — Enrollment 資料流（SDK 原生路徑）

`SpeakerEnroller.embedding(for: audioPath)`：對註冊音檔跑 diarizer → `speakerDatabase` 取**總時長最長**的 speaker embedding（短雜訊不奪主導）。`DiarizationEngine.diarize(audioPath:knownSpeakers:[(name, embedding)])`：轉 `Speaker` 預載（`.reset` mode——每次執行獨立、不累積跨執行狀態）→ turns 的 `speaker` 欄直接是名或 raw id。

### D2 — 標籤語意（Assigner 擴充）

`assign(segments:turns:knownNames:Set<String>)`：turn.speaker ∈ knownNames → 標籤原樣（如 `[Alice]`）；否則 → SPEAKER_N（ordinal 只數未知者——名字不佔序號，未知者編號穩定不受註冊命中影響）。零重疊 nil 與 tie 規則不變。

### D3 — 觸發與可見性

identification 啟用條件 = `--diarize` ∧ resolved context dir 存在 `voices/*.wav|m4a|mp3`。使用者放聲紋檔即意圖，不另設 flag；`--explain` 輸出「voices: N enrolled, M matched」。voices 為空/不存在 → 純 #25 行為（零回歸）。

### D4 — 隱私鐵律（spec 級）

`voices/` 內容為敏感生物特徵：spec 明文任何工具 SHALL NOT 上傳、commit、或以任何形式將聲紋檔/embedding 送離本機（與 CLAUDE.md「raw 第三方內容不進 remote」同級）；context-ingest skill 對 voices/ 不做任何處理。

### D5 — 驗證（半剖法，零新下載）

FLEURS speaker 匿名 → 用「同錄音剖半」保證同人：enrollment = FEMALE 錄音前半（≈5.1s）；fixture（#25 pinned，male+1s gap+female）→ 期望 female cue 標 `[TestVoice]`、male 維持 `[SPEAKER_1]`。斷言入 validate-diarization.sh（digest pin enrollment 半剖檔）。

## Implementation Contract

- `swift test` 綠：assigner 混合標籤 ×3（名字通過/未知 ordinal 穩定/名字不佔序號）+ enroller/engine seam
- live：validate script 新增斷言全過（female → 註冊名、male → SPEAKER_1、無 voices 時輸出與 #25 一致）
- `spectra validate` 綠
