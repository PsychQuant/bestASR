## Why

#25（使用者 Clarity 裁決：兩階段之一——本案 diarization、identification 為 #26）。bestASR 聲學層零 speaker 能力：多說話者錄音（會議/上課/訪談——Plaud 場景）轉寫後無從得知誰在何時說；既有 srt-proofread 的 speaker 軸為純語意推測、無聲學根據。

## What Changes

1. SPM 依賴 **FluidAudio pin v0.15.4**（Apache-2.0、Swift 6、CoreML/ANE；live probe 2026-07-03）——CoreML diarization 模型由 SDK 自 HF `FluidInference` org 下載管理（vendor-managed；支援 offline flag）
2. 新模組 `Diarize/`：`SpeakerTurn` 型別、`DiarizationEngine`（模型下載/初始化 + 全檔 diarize）、**`SpeakerAssigner` 純函式**（transcription segments × turns 以最大時間重疊指派 cue 級 `SPEAKER_N`——TDD 核心）
3. `TranscriptSegment.speaker: String?` + `TranscriptWriter` 四格式呈現（srt/vtt cue 前綴 `[SPEAKER_N] `、json 加欄位、txt 段落前綴）——僅在有 speaker 時
4. CLI `bestasr transcribe --diarize`（opt-in；首跑需網路抓模型）
5. specs：**diarization ADDED** + **cli MODIFIED**（transcribe requirement 增 --diarize 與 speaker 呈現）

## Impact

- Affected specs: diarization (ADDED), cli (MODIFIED)
- Affected code: Package.swift、Sources/BestASRKit/{Diarize/,Models/DataModels.swift,Output/TranscriptWriter.swift,CommandCore.swift}、Sources/bestasr/BestASRCommand.swift、Tests、CHANGELOG.md
- Non-goals：speaker identification / enrollment（#26，blocked by 本案）；names[] 真名自動對齊（留 srt-proofread 語意層——使用者裁決）；DER 品質基準（有真實需求再立案）；streaming/即時（batch 檔案模式 only）
