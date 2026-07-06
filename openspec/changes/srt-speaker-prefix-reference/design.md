## Context

#55：speaker-labeled SRT ground truth（`Name: text` cue 前綴）餵進 `referenceText` 會把名字算進 reference。本語料 269 cues × ~2-3 詞前綴，WER 分母與 edit distance 同時被污染。

## Goals / Non-Goals

**In**：`referenceText` 剝 speaker 前綴（heuristic）、spec delta、測試、語料登記。
**Out**：TextNormalizer、SRT 結構解析、切片策略。

## Decisions

### D1 — repeated-prefix heuristic，不加 CLI flag

前綴判定規則：cue 文字匹配 `^<prefix>: `（prefix ≤40 字元、不含 colon）者收集其 prefix；**同一 prefix 出現 ≥2 次**即判定為 speaker 標籤，該集合內的前綴全數剝除。單次出現者（正文引言「Note: ...」）保留。理由：speaker 標籤的本質特徵就是重複（對談至少兩人各說多句）；flag 會把判斷推給使用者且 corpus add 無現成參數面。Deletion test：拿掉 heuristic → Jobs & Gates reference 含 700+ 個名字 token、WER 灌高——非 pass-through。

### D2 — 剝除落在 referenceText 萃取層，cue 結構不動

`SRTCue.text` 保留原文（含前綴）——SRT 解析忠實；剝除只在 `referenceText(from:)` 聚合時發生。理由：cue 級消費者（若未來有對齊用途）仍拿得到 speaker 資訊；reference 文字是唯一該乾淨的出口。

### D3 — 語料檔案不進 git，登記走既有 `~/.bestasr/corpora/` 慣例

與 fetch-corpora.sh／validate-diarization.sh 同目錄慣例；`CorpusRow` 記 absolute path + SHA256，重登記依 audio hash upsert。repo 只進 code＋spec＋測試 fixture（合成小 SRT，非 81 分鐘語料本體）。

## Risks / Trade-offs

- ≥2 次門檻下，只說過一句話的說話人前綴會殘留——本語料三人皆多句無此問題；極端 case 殘留一個前綴的 WER 影響遠小於全滅，可接受
- 名字含 colon（如 "Dr: Smith"）不在 prefix 形狀內——SRT speaker 慣例不含此形，忽略

## Migration Plan

行為變更只影響「帶重複 colon 前綴的 SRT reference」——現有語料（osr-harvard 短句、zh/ja tsv）無此形狀，數值不動。Rollback = revert。

## Open Questions

（無）
