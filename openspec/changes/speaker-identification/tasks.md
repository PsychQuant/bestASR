## 1. TDD — Assigner 擴充

- [x] 1.1 RED：`assign(segments:turns:knownNames:)` 三案（註冊名原樣通過、未知 ordinal 不受名字影響、混合序）
- [x] 1.2 GREEN

## 2. Enrollment 與引擎

- [x] 2.1 `SpeakerEnroller`（註冊音檔 → 主導 embedding；diarizer 复用）
- [x] 2.2 `DiarizationEngine.diarize` 回 `DiarizationOutput{turns, embeddings}`——**設計修正**：實測 DiarizerManager 的 `initializeKnownSpeakers` 預載路徑不進 clustering 決策（主 run distance=inf），改走**自控 post-hoc embedding 比對**（新純函式 `SpeakerIdentifier.resolve`）——更穩健、可完全單元測試、不賭 SDK 內部
- [x] 2.3 Context：voices/ 探索（resolved dir 下 `voices/*.{wav,m4a,mp3}`）；loader 不碰 voices/（不進 ignored list）
- [x] 2.4 CommandCore：--diarize ∧ voices 存在 → enroll + 預載；explain 揭露 enrolled/matched；seam 測試（fake diarizer 帶名 turn）

## 3. 驗證與收尾

- [x] 3.1 validate-diarization.sh 延伸：半剖 enrollment（FEMALE 前半，digest pin）→ female cue = 註冊名、male = SPEAKER_1；無 voices 一致性斷言
- [x] 3.2 全套件綠；CHANGELOG（assert）；`spectra validate` 綠
