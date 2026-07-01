## 1. Python 實作歸檔（Phase 1）

- [ ] 1.1 依 D9: Python 實作遷入 archive 資料夾，用 git mv 把 bestasr/、tests/、examples/、pyproject.toml 遷入 archive/python/ 對應子路徑（git 歷史保留）。同時確認被 REMOVED 的跨平台需求（Select backend by rule-based decision table、Select model and compute type by profile scoring、Detect operating system and CPU、Detect memory and GPU、Detect acceleration backends、Detect CPU instruction sets and ffmpeg presence、Graceful degradation when a probe tool is unavailable）的實作只存在於 archive，主樹不再有 Python 執行路徑。行為：repo 根目錄無 Python 套件、archive/python/ 完整。驗證：git status 顯示 rename、ls 確認新舊路徑。

## 2. Swift Package 骨架與資料模型（Phase 2）

- [ ] 2.1 依 D1: SPM 佈局 — library BestASRKit + executable bestasr 建 Package.swift（platforms .macOS(.v14)、相依 WhisperKit / swift-argument-parser）與六個子目錄空模組；依 D10: CLI 以 swift-argument-parser 註冊六個 subcommand stub。行為：swift build 成功、bestasr --help 列出六個子指令並 exit 0。驗證：swift build + 手動執行 --help。實作 Swift 前先載入 apple-xcode-skills:swiftui-specialist 以外的相關 skill（CLI 無 UI，至少載 audit 對應規約）。
- [ ] 2.2 [P] 定義核心型別於 Sources/BestASRKit/Models/DataModels.swift：SystemInfo（chip / unified_memory_gb / has_ane / macos_version）、AudioInfo、TranscribeOptions（model / quantization / language）、Transcript / TranscriptSegment、ASRRecommendation（backend / model / quantization / data_source / measured / reason / warnings）、BenchmarkRecord（依 design Implementation Contract 欄位）、ModelRequirements。行為：型別可編譯、欄位齊備。驗證：Tests/BestASRKitTests/DataModelTests.swift 斷言欄位與預設值。
- [ ] 2.3 [P] 建 Sources/BestASRKit/Models/ModelRegistry.swift：模型清單（tiny…large-v3-turbo）、各 backend 支援的量化檔位、cold-start 用估算記憶體表與 profile 候選清單。行為：registry 查詢回傳正值與正確清單。驗證：DataModelTests 內斷言各模型估算為正、profile 清單內容。
- [ ] 2.4 依 D11: 測試策略 — Swift Testing + mock engine 建 mock engine 與共用測試 fixture（固定 Transcript / 可注入失敗）。行為：測試可在無真模型下驅動 engine 介面。驗證：swift test 收集並跑過 fixture 自測。

## 3. Detection 層（Phase 3）

- [ ] 3.1 依 D8: Detection — sysctl / ProcessInfo / AVFoundation，零 ffmpeg 實作 Detect Apple Silicon hardware profile 於 Sources/BestASRKit/Detect/SystemDetector.swift：chip（sysctl）、unified_memory_gb（ProcessInfo）、macos_version、has_ane（晶片世代查表，miss 回 unknown）、非 Apple Silicon（含 Rosetta）明確錯誤。行為：本機回報正確輪廓；未知晶片 ANE 為 unknown 不拋錯。驗證：Tests/BestASRKitTests/DetectionTests.swift（查表注入 + 本機 smoke 斷言非空 chip 與正記憶體）。
- [ ] 3.2 [P] 實作 Probe audio file properties 於 Sources/BestASRKit/Detect/AudioProber.swift：AVFoundation 讀 duration / format / sample_rate / channels；缺檔或非音訊拋明確錯誤。行為：合法檔填滿欄位、壞檔具名報錯。驗證：DetectionTests 用測試音檔與壞檔斷言。
- [ ] 3.3 [P] 移植語言解析（explicit verbatim / auto → nil 交給 engine）到 Sources/BestASRKit/Detect/Language.swift，並提供 CER/WER 語言判定 helper（zh/ja/ko → cer，其餘 → wer）供 benchmark 使用。行為：zh→zh、auto→nil、zh 判 cer、en 判 wer。驗證：DetectionTests 參數化斷言。

## 4. Metrics 與 SRT ground truth（Phase 4）

- [ ] 4.1 [P] 依 D5: `.srt` ground truth 解析歸屬 benchmark capability 實作 Parse SRT reference into ground truth 於 Sources/BestASRKit/Benchmark/SRTParser.swift：解析 index / HH:MM:SS,mmm --> HH:MM:SS,mmm / 文字行為 SRTCue 陣列，reference text = 依序串接；無合法 timecode 拋具名解析錯誤。行為：合法 SRT 得有序 cues、壞檔拒收且不啟動轉錄。驗證：Tests/BestASRKitTests/MetricsTests.swift 用 spec SBE（"hello"/"world"）與壞檔案例。
- [ ] 4.2 [P] 依 D4: 準確度度量 — CER（中文）/ WER（英文），依語言自動選 實作 Sources/BestASRKit/Benchmark/TextNormalizer.swift（NFKC、去標點、全形轉半形、lowercase、空白摺疊）與 Sources/BestASRKit/Benchmark/ErrorRate.swift（Levenshtein；CER 字元級 / WER 空白分詞），完成 Compute accuracy metric selected by language。行為：zh 用 cer、en 用 wer、報表註記 metric kind。驗證：MetricsTests 鎖 spec SBE 值（「今天天氣好」vs「今天天很好」CER=0.2；"the cat sat down" vs "the cat sat" WER=0.25）與正規化案例。

## 5. Engine 層（Phase 5）

- [ ] 5.1 依 D3: Backend 集合 — WhisperKit primary + whisper.cpp secondary 定義 Common engine interface 於 Sources/BestASRKit/Engines/Engine.swift：is_available / transcribe(audio, options) / estimate_requirements，options 帶 quantization；template-method 正規化 Transcript 並把失敗包成 typed TranscriptionError（Transcription failure is surfaced、Availability detection is graceful、Transcription returns a normalized Transcript 均由此介面層滿足）。行為：mock 注入下 segments 依 start 排序、id 從 1 編號、失敗拋 typed error。驗證：Tests/BestASRKitTests/EngineTests.swift。
- [ ] 5.2 實作 WhisperKitEngine 於 Sources/BestASRKit/Engines/WhisperKitEngine.swift：先以 context7 / 官方 repo 核對 WhisperKit 當前 API（模型載入、ComputeOptions、量化變體命名），availability 誠實回報。行為：可用性正確、transcribe 經 mock raw 層測正規化。驗證：EngineTests mock 路徑 + 本機 smoke（實作末段跑一次真轉錄）。
- [ ] 5.3 實作 WhisperCppEngine 於 Sources/BestASRKit/Engines/WhisperCppEngine.swift：驗證 whisper.cpp SwiftPM 整合方式（官方 Package.swift / 社群 wrapper / C target 擇一可建置；卡關則 fallback subprocess 呼叫 whisper-cli，介面不變）。行為：GGUF 量化變體可指定、不可用時 is_available 回 false 不拋。驗證：EngineTests mock 路徑；整合方式決定記入 commit message。

## 6. Benchmark 管線（Phase 6，核心）

- [ ] 6.1 實作 Enumerate candidate configurations 於 Sources/BestASRKit/Benchmark/BenchmarkRunner.swift：backend × model × 量化 交叉、跳過不可用 backend 並記 note、支援 backend/model 過濾。行為：不可用 backend 零候選 + note；過濾器縮小集合。驗證：Tests/BestASRKitTests/BenchmarkTests.swift 以 mock 可用性斷言。
- [ ] 6.2 依 D7: 速度與記憶體度量 實作 Measure speed and memory per candidate：暖身載入後計時、RTF = 轉錄秒 ÷ 音訊秒、下載時間另計、峰值記憶體近似量測並註記方式。行為：RTF 排除下載、報表含 peak-mem。驗證：BenchmarkTests 以 mock 計時來源斷言 RTF 計算（60 秒音檔 5 秒轉錄 → RTF=5/60）。
- [ ] 6.3 實作 Warn-continue on per-candidate failure：單候選失敗記原因續跑、全滅才失敗。行為：3 候選 1 失敗 → 2 個完成排名 + 失敗列原因；全滅 → runtime 錯誤。驗證：BenchmarkTests 注入失敗 mock。
- [ ] 6.4 實作 Rank candidates and report results：profile 權重排名、報表欄位（backend / model / quant / error rate+metric kind / x-realtime / peak-mem / rank）、--json 機器可讀輸出。行為：accurate profile 下 spec SBE 排名（whisperkit large-v3-turbo 第 1）。驗證：BenchmarkTests 鎖 SBE 表。
- [ ] 6.5 依 D6: Benchmark 快取 — 機器本地 JSON 實作 Persist benchmark results to a machine-local cache 於 Sources/BestASRKit/Benchmark/BenchmarkCache.swift：鍵 (backend, model, quantization, language)、同鍵覆蓋、記錄 chip / macos_version / app_version / measured_at。行為：重測同鍵單筆保留新 timestamp；router 可讀。驗證：BenchmarkTests 對暫存目錄讀寫斷言。

## 7. Router 兩層（Phase 7）

- [ ] 7.1 依 D2: 兩層路由 — benchmark 實測為主、cold-start prior 為 fallback 實作 Rank candidates by measured benchmark data 於 Sources/BestASRKit/Router/Router.swift：只消費 backend 可用且語言匹配的紀錄、chip 不符視為無快取、profile 權重可翻轉贏家（spec SBE：accurate 選 whisperkit large-v3-turbo、fast 選 whisper.cpp small q5）、data_source=measured。行為：如 spec 兩個 scenario。驗證：Tests/BestASRKitTests/RouterTests.swift 鎖 SBE 表。
- [ ] 7.2 實作 Cold-start prior when no benchmark data exists 於 Sources/BestASRKit/Router/ColdStartPrior.swift：whisperkit 優先、profile 候選清單選最準且放得下者、data_source=cold_start_prior、reason 建議跑 benchmark；含 Downgrade model when memory is insufficient（large-v3→…→tiny 逐步 warning，僅 cold-start 適用）。行為：空快取 balanced → whisperkit + balanced 清單模型 + 建議語句；降級表（fits medium only → medium / 1 warning）。驗證：RouterTests 參數化。
- [ ] 7.3 實作 Honor explicit backend override with fallback 與 Handle absence of any available backend：指定不可用 → fallback + warning；雙 backend 全不可用 → 具名錯誤含安裝指引。行為：如 spec scenarios。驗證：RouterTests。
- [ ] 7.4 實作 Produce an explainable recommendation：ASRRecommendation 含 quantization / data_source / measured 摘要，measured 時 reason 引用實測數字（error rate + 速度）。行為：measured 推薦 reason 含數字；cold-start 推薦 measured 為 null 仍有 reason。驗證：RouterTests 斷言 reason 內容。

## 8. Output 與 CLI 整合（Phase 8）

- [ ] 8.1 [P] 於 Sources/BestASRKit/Output/TranscriptWriter.swift 重新實作四種輸出（txt / json / srt / vtt），行為契約沿用既有 transcript-output living spec（SRT 逗號毫秒 / VTT 點毫秒與 WEBVTT header / 預設 txt / 未知格式列支援清單報錯）。行為：spec SBE 逐字輸出。驗證：Tests/BestASRKitTests/OutputTests.swift 鎖 SBE。
- [ ] 8.2 完成 Provide help and a stable command surface 與各指令 wiring：diagnose（硬體輪廓 + 推薦 + 理由，無需音檔）、transcribe（--profile/--backend/--model/--language/--format/--output/--explain，explain 走 stderr 不污染輸出檔）、list-backends / list-models。行為：--help 六指令 exit 0；transcribe 預設 txt 且路徑衍生。驗證：Tests/BestASRKitTests/CLITests.swift。
- [ ] 8.3 完成 benchmark command：接 BenchmarkRunner + SRTParser + cache，--reference 缺失/解析失敗 → usage-error exit 且不啟動轉錄；全滅 → runtime exit；--json 輸出。行為：如 cli spec scenarios。驗證：CLITests（mock engine 注入）。
- [ ] 8.4 完成 recommend command emits JSON only：stdout 單一 JSON 含 backend / model / quantization / data_source / measured / reason；有快取時 data_source=measured 並帶數字。依 D10: 錯誤模型 — typed error + 分級 exit code 統一 0/1/2 exit 對映（Non-zero exit on failure 行為沿用既有 cli living spec）。行為：JSON 可 parse、鍵齊備；缺檔 exit 2。驗證：CLITests。

## 9. 收尾（Phase 9）

- [ ] 9.1 重寫 README.md：Swift 版定位（benchmark-driven Apple Silicon ASR router）、安裝（SPM / 未來 Homebrew 佔位不承諾）、六指令 quick start（含 benchmark 工作流：先 benchmark 後 recommend）、archive/python/ 位置註記。行為：README 反映 Swift 現狀且強調實測解釋。驗證：內容審閱 + 指令範例照打可跑。
- [ ] 9.2 本機 smoke 驗收（design Implementation Contract 驗收段）：swift test 全綠；bestasr diagnose 報 M5 Max 輪廓；對短音檔 + 對應 .srt 跑 bestasr benchmark 產出排名並寫快取；隨後 bestasr recommend 的 data_source 為 measured。行為：契約全項成立。驗證：逐項執行並記錄輸出於 PR / issue comment。
