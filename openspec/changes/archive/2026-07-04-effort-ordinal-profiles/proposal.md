# Effort-ordinal profiles + machine-state auto default + README rewrite

#29（clarity 三裁決已定）：使用者要 Claude Code effort 式的品質標籤。現況三個落差：

1. `--profile fast|balanced|accurate` 的 `accurate` 是 0.8/0.2 加權混合——不是使用者定義的「不計任何時間要最準」（純 argmax）。頂檔心智模型應「不妥協」。
2. 標籤軸裁決為 **Claude Code 式序數 low/medium/high/xhigh/max**（5 檔，使用者點名 xhigh：「更能直覺感受」），取代語意標籤、不留 alias。
3. 「預設根據電腦的狀態」裁決**納入動態狀態**（thermal pressure + Low Power Mode）——預設檔位在機器有壓力時自動降檔；顯式 `--profile` 永不被覆蓋。

README 同時全面落後 0.7.0（diarize/voices 0 處），重寫為使用者旅程 + 標籤契約表 + 全指令參考。

## What

1. `RouterProfile` → 序數 5 檔：low 0.267 / medium 0.5 / high 0.8 / xhigh 0.9 / **max 1.0**；max 同分 tie-break 取快者（Ranking 顯式化，消除非穩定排序）
2. `--profile` 預設 **`auto`** sentinel：無壓力 → medium；thermal ≥ serious 或 LPM → low，降檔進 explain reasons。bench 的 profile 預設 medium（報表排序用，無降檔語意）
3. system-detection 增 `DynamicHostState` probe（@Sendable seam、失敗降級為無壓力）
4. 舊值 fast/balanced/accurate → 錯誤訊息附遷移對照（fast→low、balanced→medium、accurate→high 或 max）
5. README 重寫 + CHANGELOG

## Impact

- specs：asr-routing（Rank candidates、Cold-start prior 兩個 MODIFIED）、system-detection（ADDED dynamic conditions）、cli（transcribe MODIFIED）、**benchmark（Rank-and-report MODIFIED：accurate→high Example + report-ranking `--profile` 序數集，#29 verify #4 雙軌漏網）**
- code：DataModels / ModelRegistry / Ranking / ColdStartPrior / SystemDetector 域 / CommandCore / BestASRCommand / README / CHANGELOG
