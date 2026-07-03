## Why

#26（兩階段裁決之二，#25 已 ship）：diarization 只給匿名 SPEAKER_N；會議/上課場景要的是「這是誰」。FluidAudio v0.15.4 原生支援 known-speaker recognition（live probe：`initializeKnownSpeakers` 預載 → `speakerId` 直接回註冊名，cosine threshold SDK 內建），不需自建比對器。

## What Changes

1. **Enrollment 慣例**：resolved context dir 下 `voices/<name>.wav`（檔名 stem = 標籤名；三層 precedence 免費繼承；零新 CLI surface）。**Local-only 鐵律進 spec**：聲紋屬敏感生物特徵——任何工具不得上傳/commit voices/
2. `SpeakerEnroller`：註冊音檔 → 主導 speaker embedding（复用 diarizer）
3. `DiarizationEngine.diarize(audioPath:knownSpeakers:)`：預載後 turns 直接帶名
4. `SpeakerAssigner` 擴充：註冊名原樣通過、未知維持 SPEAKER_N ordinal（且名字不佔用 ordinal 序號）
5. 觸發語意：`--diarize` + resolved context dir 有 `voices/` → identification 自動啟用；`--explain` 註記
6. `scripts/validate-diarization.sh` 延伸 identification 斷言（半剖 enrollment 法）
7. specs：diarization MODIFIED（named labels + local-only）+ context-calibration MODIFIED（voices/ 資料夾）

## Impact

- Affected specs: diarization (MODIFIED), context-calibration (MODIFIED)
- Affected code: Sources/BestASRKit/{Diarize/,Context/,CommandCore.swift}、scripts/validate-diarization.sh、Tests、CHANGELOG.md
- Non-goals：speakerThreshold 可調參數（SDK 預設 0.65 + design 記載，誤匹配實證再開）；embedding 快取；enrollment 專用 CLI 指令（clarity 已裁決慣例資料夾）
