## Context

#50：FluidAudio 0.15.4 內建 ParaformerManager／SenseVoiceManager，皆 `load()` → `transcribe(audioURL:) -> String`。ParakeetEngine（#35）是既有 conformer 模板。TextNormalizer.foldHanToSimplified（#34 D7）已解 zh CER 的簡繁比較問題。

## Goals / Non-Goals

**In**：兩個 backend 接線、grid/router/CLI、語言 hint、zh-TW 實測。
**Out**：s2t 交付後處理、Qwen3-ASR、WeightVerifier 掛線（#52 未 merge，residue）。

## Decisions

### D1 — 兩個獨立 backend，不合併為單一「funasr」backend

Paraformer（zh 專用 large）與 SenseVoice（多語 small）的語言面、模型量級、量測數據都不同——合併會讓 grid row 與 measured ranking 失去分辨力。命名沿 `fluid-` 前綴慣例。

### D2 — String-only 輸出映射為單段全文 raw segment

兩 manager 無 confidence／timings → `RawSegment(start: 0, end: probe duration, text: full, confidence: nil)`——與 ParakeetEngine 的 no-timings fallback 同形。家族限制寫進 spec（deletion test：假造 timings 會污染 SRT 時間軸——誠實單段優於假精度）。

### D3 — SenseVoice v1 一律 auto-detect，不猜語言 embed index

FluidAudio 0.15.4 只 export `defaultLanguage: Int32 = 0`（auto），語言 embed index 對照表未公開——寫死猜測值錯了會靜默劣化品質且難察覺。v1 一律傳 auto（SenseVoice 的設計主路徑，非降級）；顯式 hint 映射待上游 export 常數（residue）。Paraformer 無語言參數（zh 專用，grid 註記）。

### D4 — 不加 hard language gate（沿 #35）

Router 對 zh 請求仍列所有 available backends；measured CER 自然排序。Grid 的 priority 欄維持家族內排序語意。

### D5 — 實測協定（issue acceptance）

cv-zhtw-1..4 各對兩家族 `bestasr benchmark --backends fluid-paraformer,fluid-sensevoice`（或逐一 transcribe+CER），與 store 內 whisper baseline 對照；記錄：CER、RTF、輸出字系（簡/繁抽查）。數字進 PR body 與 issue comment——「勝者進候選池」在 v1 語意 = 兩者都接線，數據見真章。

## Risks / Trade-offs

- 輸出若為簡體：CER 比較公平（fold），交付字系錯位記錄在案（另案處理）
- 下載量：Paraformer large + SenseVoice small 首跑數百 MB——README benchmark 警語涵蓋
- SenseVoice actor 的併發語意與 CreateOnceStore 疊加——每 model key 單 pipeline，CLI 序列呼叫不觸發競態（Parakeet 先例）

## Migration Plan

純增量（新 backend 不影響既有路由的 measured 數據）。Rollback = revert。

## Open Questions

（無）
