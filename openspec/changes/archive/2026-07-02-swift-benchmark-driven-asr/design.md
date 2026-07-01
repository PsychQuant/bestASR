## Context

bestASR Python MVP（change `bestasr-mvp`，已歸檔）是跨平台 heuristic 路由器：偵測硬體 → 規則決策表選 backend → 靜態特性表選模型。使用者於 issue #2 定調兩件事：(1) re-platform 成 Apple Silicon 專屬 Swift 原生 CLI；(2) 路由從「猜」升級為「量」——benchmark 是核心能力，ground truth 用 `.srt`。

限制與現況：
- 目標機器僅 Apple Silicon（arm64）、macOS 14+。開發機為 M5 Max / 137 GB unified memory。
- WhisperKit 與 whisper.cpp 是外部相依，實際 API 以實作時的官方文件為準（風險見下）。
- 5 份語言中立 living spec 已存在；本 change 以 delta 修 4 份 + 新增 1 份，`transcript-output` 不動。
- 全域規約：實作 Swift code 前必須載入 apple-xcode-skills 對應 skill（apply 階段執行，propose 不寫 code）。

## Goals / Non-Goals

**Goals:**

- `bestasr benchmark <audio> --reference <gt.srt>`：實測本機所有可用候選，產出 CER/WER + RTF + 峰值記憶體排名，寫入快取。
- `recommend` / `transcribe` 消費快取：有實測數據時據此推薦並在解釋中引用數字；無數據時走 cold-start prior 並提示跑 benchmark。
- WhisperKit + whisper.cpp 雙 backend，共同 engine 介面，graceful 可用性偵測。
- Apple 硬體偵測（晶片、unified memory、ANE、macOS 版本）；AVFoundation 音訊探測，零 ffmpeg 相依。
- 全部行為有 Swift Testing 測試（engine 以 mock 注入，不需真模型）。
- 舊 Python 實作完整保存於 archive 資料夾。

**Non-Goals（明確排除）:**

- Intel Mac、Linux、Windows 支援（arm64-only；跨平台參考實作保存在 archive）。
- mlx-swift backend（與 WhisperKit 底層 MLX 重疊）。
- 內建標準 benchmark 資料集（使用者自備音檔 + `.srt` ground truth；資料集策展是後續版本議題）。
- 即時串流轉錄、diarization、翻譯、摘要、雲端 API、Web UI（沿襲 v1 非目標）。
- benchmark 結果跨機器共享 / 上傳 leaderboard（快取是機器本地的）。
- 字幕時間軸對齊誤差度量（v1 只比文字 CER/WER；時間碼對齊列為未來擴充）。

## Decisions

### D1: SPM 佈局 — library BestASRKit + executable bestasr

邏輯全放 library target `BestASRKit`（Detect / Models / Engines / Benchmark / Router / Output 六個子目錄），executable target `bestasr` 只做 argument parsing 與 wiring（swift-argument-parser）。Platforms 宣告 `.macOS(.v14)`。
- 理由：library/executable 分離讓 Swift Testing 直接測 library，不用 spawn process；未來若要出 GUI 或 XPC service 可重用 Kit。
- 替代：單一 executable target。否決——測試只能走 subprocess，慢且脆。

### D2: 兩層路由 — benchmark 實測為主、cold-start prior 為 fallback

Router 決策順序：(1) 讀機器快取中符合（backend 可用 × 語言匹配）的實測紀錄 → 以 profile 權重排名選最高分；(2) 無可用紀錄 → cold-start prior（靜態候選清單 + 記憶體降級鏈，邏輯承襲 Python 版）並在 reason 註明「cold start——跑 `bestasr benchmark` 可獲得針對這台機器的實測推薦」。
- 理由：benchmark 讓「best」誠實；prior 保證未 benchmark 前開箱即用。
- 替代：強制先 benchmark 才能 transcribe。否決——第一次使用體驗太差，且 benchmark 要下載多個模型，成本高。

### D3: Backend 集合 — WhisperKit primary + whisper.cpp secondary

WhisperKit 走 CoreML/ANE（系統整合、ANE 加速）；whisper.cpp 走 GGUF（量化檔位彈性 q4/q5/q8、模型版本多）。兩者構成真實取捨空間，是 benchmark 與 router 的存在理由（deletion test：拿掉任一個，router 仍有事可做；拿掉兩個之一變單一 backend 則 router 退化為 pass-through）。
- 替代：見 proposal Alternatives（單 WhisperKit / 加 mlx-swift 均否決）。

### D4: 準確度度量 — CER（中文）/ WER（英文），依語言自動選

以 Levenshtein 編輯距離計算：CER 以字元為單位（中文無詞邊界，WER 不適用）；WER 以空白分詞。語言取自 benchmark 時的 `--language` 或 ground truth 偵測；`zh`/`ja`/`ko` 等無空白分詞語言用 CER，其餘預設 WER，報表註明所用度量。
- 文字正規化（比較前雙方都做）：Unicode NFKC、去頭尾空白、全形轉半形、移除標點、英文轉小寫、空白序列摺疊。正規化規則集中單一函式，測試鎖行為。
- 理由：不正規化的 CER 會被標點/全半形噪音淹沒，量到的不是模型品質。

### D5: `.srt` ground truth 解析歸屬 benchmark capability

SRT 解析器（index / `HH:MM:SS,mmm --> HH:MM:SS,mmm` / 文字行）放 `Sources/BestASRKit/Benchmark/SRTParser.swift`；`transcript-output` spec 不動。
- 理由：輸入解析是 benchmark 的關注點；writer capability 保持純輸出。discuss 結論寫「transcript-output 小改」，本設計改判為「不改」——聚合力更好，且避免 writer spec 混入 reader 語意。
- v1 只取 cue 文字串接為 reference text；時間碼保留於解析結果但不參與度量（見 Non-Goals）。

### D6: Benchmark 快取 — 機器本地 JSON

路徑 `~/.bestasr/benchmarks.json`。每筆紀錄鍵：(backend, model, quantization, language)；值：cer_or_wer、metric_kind、rtf、peak_memory_gb、audio_duration、measured_at、chip、macos_version、app_version。同鍵新測覆蓋舊測（保留 measured_at 供追溯）。
- Router 消費規則：只用 backend 當前可用、且 language 匹配（或紀錄為語言無關）的紀錄；chip 不匹配（快取搬機）視為無效。
- 替代：SQLite。否決——單機少量紀錄，JSON 可讀可 diff，夠用。

### D7: 速度與記憶體度量

RTF（real-time factor）= 轉錄 wall-clock 時間 ÷ 音訊長度；報表同時給 x-realtime（1/RTF）。峰值記憶體以 task_info / ProcessInfo 量測進程峰值增量（實作細節允許粗粒度，報表註明量測方式）。每候選先跑一次暖身（模型載入）再計時，模型下載時間不計入 RTF 但單獨回報。
- 理由：使用者要的是「這台機器上誰快」，模型下載是一次性成本，混入會失真。

### D8: Detection — sysctl / ProcessInfo / AVFoundation，零 ffmpeg

晶片名 `sysctl machdep.cpu.brand_string`；unified memory `ProcessInfo.physicalMemory`；macOS 版本 `ProcessInfo.operatingSystemVersion`；ANE 以晶片世代查表判定可用性（Apple 無公開 ANE 探測 API，查表 + 保守 fallback）。音訊 duration/format/sampleRate/channels 用 AVFoundation（`AVURLAsset` / `AVAudioFile`）。非 Apple Silicon（含 Rosetta 下誤跑）→ 明確錯誤退出。
- 理由：全部系統框架，零外部工具相依；Python 版的 ffmpeg graceful-degradation 需求整段退役。

### D9: Python 實作遷入 archive 資料夾

`bestasr/`、`tests/`、`examples/`、`pyproject.toml` 以 git mv 遷入 `archive/python/` 對應子路徑，git 歷史保留。README 重寫為 Swift 版並註明 archive 位置。遷入後該路徑受 archive 保護規約管轄（不再修改）。
- 理由：使用者 Q1 明示「舊的東西可以放到 archive 資料夾」；它是唯一跨平台參考實作，日後若回跨平台可考古。

### D10: 錯誤模型 — typed error + 分級 exit code

沿襲 Python 版契約：exit 0 成功、1 runtime 失敗（無 backend、轉錄失敗、benchmark 全滅）、2 使用錯誤（缺檔、`.srt` 解析失敗、非法參數）。Engine 拋 typed `TranscriptionError`；benchmark 單一候選失敗記錄後續跑（warn-continue），全部失敗才非零退出。

### D11: 測試策略 — Swift Testing + mock engine

框架用 Swift Testing（非 XCTest）。Engine 協定注入 mock（回固定 Transcript / 拋錯），router、benchmark、metrics、output、CLI 全部可在無真模型、無網路下測。CER/WER 與 SRT 解析用 spec 的 SBE 範例值鎖定。真實 WhisperKit/whisper.cpp 整合路徑以 `isAvailable()` 誠實回報 + 手動 smoke 驗證（實作階段在本機跑一次真轉錄）。

## Implementation Contract

**指令面（可觀察行為）：**

- `bestasr --help`：列出 `diagnose` / `recommend` / `transcribe` / `benchmark` / `list-backends` / `list-models`，exit 0。
- `bestasr diagnose`：印 Apple 硬體輪廓（晶片 / unified memory / ANE / macOS）+ 推薦 + 理由；無需音檔；exit 0。
- `bestasr recommend <audio>`：stdout 僅一個 JSON 物件，含 `backend`、`model`、`quantization`、`profile`、`language`、`data_source`（`"measured"` 或 `"cold_start_prior"`）、`measured`（有實測時含 `metric_kind`/`error_rate`/`rtf`，無則 null）、`reason[]`、`warnings[]`。不轉錄。
- `bestasr transcribe <audio> [--profile] [--backend] [--model] [--language] [--format] [--output] [--explain]`：轉錄並寫檔（預設 txt、路徑衍生自輸入檔名）；`--explain` 把 reason/warnings 印到 stderr，不污染輸出檔。
- `bestasr benchmark <audio> --reference <gt.srt> [--language] [--backends] [--models]`：枚舉本機可用候選 → 逐一轉錄 → 產出排名表（stdout，欄位：backend / model / quant / CER 或 WER / x-realtime / peak-mem / rank）→ 寫入 `~/.bestasr/benchmarks.json`；`--json` 時輸出機器可讀結果。單一候選失敗印 warning 續跑；全部失敗 exit 1；`--reference` 缺失或解析失敗 exit 2。
- `bestasr list-backends` / `list-models`：列 backend 可用性 / 模型與量化檔位。

**資料形狀（核心新型別）：**

- `BenchmarkRecord`：backend / model / quantization / language / metricKind（`cer`|`wer`）/ errorRate（0–1）/ rtf / peakMemoryGB / audioDuration / measuredAt / chip / macosVersion。
- `ASRRecommendation` 增欄：`quantization`、`dataSource`（measured | coldStartPrior）、`measured`（optional BenchmarkRecord 摘要）。
- SRT 解析結果：`[SRTCue(index, start, end, text)]`；reference text = cue 文字依序串接。

**度量定義（可驗證）：**

- CER = 字元級 Levenshtein(normalized(hyp), normalized(ref)) ÷ len(normalized(ref))；WER 同式但以空白分詞後的 token 為單位。
- 正規化：NFKC → 去標點 → 全形轉半形 → lowercase → 空白摺疊。
- RTF = wall-clock 轉錄秒數 ÷ 音訊秒數（暖身後計時，下載時間另計）。

**驗收（可驗證）：**

- `swift test` 綠：metrics（CER/WER 對 SBE 範例值）、SRT parser（合法/非法輸入）、router（measured 排名 / cold-start / override fallback / 無 backend）、benchmark runner（mock engine 下 warn-continue 與全滅路徑）、output writers、CLI exit codes。
- 本機 smoke：`bestasr diagnose` 正確報 M5 Max 輪廓；`bestasr benchmark` 對一段短音檔 + 對應 `.srt` 產出排名並寫快取；隨後 `bestasr recommend` 的 `data_source` 為 `"measured"`。

**Scope 邊界：**

- In scope：上述指令面、兩 backend、benchmark 管線、兩層 router、Apple detection、四種輸出、Python archive 遷移、README。
- Out of scope：Non-Goals 全部（Intel / 跨平台 / mlx-swift / 串流 / diarization / 資料集內建 / 跨機器共享 / 時間軸對齊度量）。

## Risks / Trade-offs

- [WhisperKit API 與模型倉庫演進快，propose 時的假設可能過期] → 實作第一步先以 context7 / 官方 repo 核對 API；engine 介面抽象吸收差異。
- [whisper.cpp 的 SwiftPM 整合方式（官方 Package.swift vs 社群 wrapper vs 手動 C target）需實測] → 實作時擇一驗證可建置後才續；若 C interop 卡關，fallback 為 subprocess 呼叫 whisper-cli 二進位（介面不變，engine 內部差異）。
- [ANE 無公開探測 API，查表可能漏新晶片] → 查表 miss 時保守回報 unknown 並繼續（ANE 只是 reason 素材，不是 gate）。
- [benchmark 需真模型與長轉錄時間，CI 不可行] → 依 D11 全部 mock；真實路徑靠本機 smoke，README 註明。
- [峰值記憶體量測粒度粗（進程級，含框架 overhead）] → 報表註明量測方式；v1 接受近似值，排名以 error rate 與 RTF 為主。
- [快取跨 app 版本語意漂移（模型更新後舊數據失真）] → 紀錄含 app_version 與 measured_at；v1 不自動失效，`benchmark` 重跑即覆蓋；報表顯示量測日期。
