## 1. 專案骨架與資料結構（Phase 1）

- [x] 1.1 [P] 建立 pyproject.toml + `bestasr` 套件骨架 + `bestasr` entry point，依 D1: 五層單向管線架構（CLI → Detection → Routing → Engine → Output）建立各層空模組。行為：`bestasr --help` 印出 usage 並退出 0。驗證：手動執行 `bestasr --help` 與 pytest 匯入套件成功。
- [x] 1.2 [P] 定義 dataclasses `SystemInfo` / `AudioInfo` / `ASRRecommendation` / `Transcript` / `TranscriptSegment` / `ModelRequirements`，欄位型別如 design Implementation Contract。行為：可匯入且欄位齊備。驗證：pytest 斷言各 dataclass 欄位存在與型別。
- [x] 1.3 建立 pytest 框架與共用 fixtures（假 `SystemInfo` / `AudioInfo` / `Transcript`），供 router 與 output 測試免真轉錄。行為：測試可獨立餵入假資料。驗證：`pytest -q` 能收集並執行到骨架測試。

## 2. Detection 層（Phase 2）

- [x] 2.1 [P] 實作 Detect operating system and CPU，依 D7: Detection 以標準庫 + psutil + import 探測為主，填入 `SystemInfo.os` / `cpu`。行為：任一平台回報非空 os/cpu。驗證：`tests/test_hardware_detection.py` 斷言非空字串。
- [x] 2.2 [P] 實作 Detect memory and GPU（`ram_gb` / `gpu` / `vram_gb`），RAM 用 psutil、缺件降級。行為：CPU-only 機器 gpu/vram 為 null、ram_gb 為正。驗證：monkeypatch psutil 缺失情境測試。
- [x] 2.3 [P] 實作 Detect acceleration backends（`has_cuda` / `has_metal` / `has_mlx`）以 import/查詢探測，呼應 D6 的 graceful 精神。行為：探測 ImportError 被吞、旗標回 false。驗證：模擬 ImportError 斷言 false 且不拋例外。
- [x] 2.4 [P] 實作 Detect CPU instruction sets and ffmpeg presence（`has_avx2` / `has_avx512` / `has_ffmpeg` via `shutil.which`）。行為：ffmpeg 在 PATH 時 has_ffmpeg 為真。驗證：monkeypatch PATH 測試 true/false。
- [x] 2.5 實作 Probe audio file properties（ffprobe 優先），涵蓋 D8: 音訊探測與語言偵測 的音訊面。行為：有效檔填入 duration/format/sample_rate/channels。驗證：對測試音訊斷言欄位值。
- [x] 2.6 實作 Determine transcription language（explicit 用 verbatim、auto 設 null 交給 engine），對應 D8: 音訊探測與語言偵測 的語言面。行為：`zh`→`zh`、`auto`→null。驗證：兩情境單元測試。
- [x] 2.7 實作 Graceful degradation when a probe tool is unavailable（缺 ffmpeg/psutil 時降級 + 記錄 note）。行為：缺 ffmpeg 以副檔名推斷 format 並附 warning note，不拋。驗證：缺件情境測試斷言有 note 且不 raise。

## 3. Routing 層（Phase 3，核心）

- [x] 3.1 實作 D9: Profile 權重表（fast / balanced / accurate 的 speed/accuracy/memory_fit/stability），預設 balanced。行為：回傳固定權重、未指定用 balanced。驗證：`tests/test_router.py` 斷言權重值與預設。
- [x] 3.2 實作 `models/registry` 與 `models/requirements` 靜態表，支撐 Estimate model requirements。行為：每個支援模型有正的估算記憶體需求。驗證：對每個模型名斷言 `ModelRequirements` 正值。
- [x] 3.3 實作 Select backend by rule-based decision table，即 D3: Backend 選擇決策表（規則優先序），落實 D2: Router 以 rule-based 為主、scoring 為輔。行為：Apple Silicon→`mlx-whisper`、CUDA→`faster-whisper`、CPU-only→`whisper.cpp`。驗證：三情境 test_router 斷言 backend + reason。
- [x] 3.4 實作 scorer 與 Select model and compute type by profile scoring，含 D5: compute_type 選擇規則。行為：相同可行性下 profile 決定模型、compute_type 依 backend/記憶體。驗證：profile→model 對照表測試。
- [x] 3.5 實作 Downgrade model when memory is insufficient，即 D4: 記憶體不足時的模型降級鏈（large-v3 → medium → small → base → tiny）。行為：不合則沿鏈降級並逐步記 warning。驗證：降級步驟對照表測試。
- [x] 3.6 實作 Honor explicit backend override with fallback。行為：指定 backend 不可用時 fallback 到次佳並加 warning。驗證：指定 `faster-whisper` 不可用→`whisper.cpp`+warning 測試。
- [x] 3.7 實作 Produce an explainable recommendation（`reason` 非空、`warnings` 具備）。行為：任何推薦帶至少一則 reason。驗證：斷言 `ASRRecommendation.reason` 非空。
- [x] 3.8 實作 Handle absence of any available backend。行為：無可用 backend 時拋清楚錯誤並列安裝指引。驗證：全部 backend 不可用情境斷言 raises 且訊息含 backend 名。

## 4. Output 層（Phase 4）

- [x] 4.1 [P] 實作 Write plain text output。行為：txt 檔含完整 transcript text。驗證：`tests/test_output_formats.py` 斷言內容。
- [x] 4.2 [P] 實作 Write JSON output（模組命名 `json_writer` 規避 stdlib shadowing）。行為：輸出可 `json.loads` 且含 text/language/duration/backend/model/segments。驗證：parse + keys 斷言。
- [x] 4.3 [P] 實作 Write SRT subtitles（`HH:MM:SS,mmm`、`-->`、1-based index）。行為：符合 spec SBE 範例。驗證：對範例 segment 斷言逐字輸出。
- [x] 4.4 [P] 實作 Write WebVTT subtitles（`WEBVTT` header、`HH:MM:SS.mmm` 點分隔）。行為：首行 WEBVTT、點分隔毫秒。驗證：對範例 segment 斷言逐字輸出。
- [x] 4.5 實作 Select writer by format with a default。行為：未指定用 txt、未知格式拋錯列支援清單。驗證：預設與非法格式兩測試。

## 5. Engine 層（Phase 5）

- [x] 5.1 實作 Common engine interface（`is_available` / `transcribe` / `estimate_requirements`），即 D6: BaseEngine 介面與 backend 可用性偵測（graceful degrade）。行為：三 backend 皆具此介面。驗證：斷言各 backend 具備指定方法簽章。
- [x] 5.2 實作 Availability detection is graceful（lazy import 探測、缺件回 false）。行為：未安裝套件回 false 不拋 ImportError。驗證：模擬未安裝斷言 false。
- [x] 5.3 實作 faster-whisper engine，滿足 Transcription returns a normalized Transcript 與 Estimate model requirements。行為：成功轉錄回排序 segments 與 backend/model metadata。驗證：mock 底層庫測試 Transcript 結構。
- [x] 5.4 實作 whisper.cpp engine（binding 或 subprocess）同介面。行為：`is_available` 誠實回報、transcribe 回正規化 Transcript。驗證：mock 執行路徑測試。
- [x] 5.5 實作 mlx-whisper engine 同介面。行為：Apple Silicon 上可用、transcribe 回正規化 Transcript。驗證：mock 底層庫測試。
- [x] 5.6 實作 Transcription failure is surfaced。行為：decode 失敗或缺 runtime 時拋清楚 typed error，不回半殘 Transcript。驗證：餵壞輸入斷言 raises。

## 6. CLI 與收尾（Phase 6）

- [x] 6.1 實作 D10: CLI 以標準庫 argparse 實作，滿足 Provide help and a stable command surface。行為：`bestasr --help` 列出五個子指令並 exit 0。驗證：執行 --help 斷言子指令與 exit code。
- [x] 6.2 實作 diagnose command。行為：`bestasr diagnose` 印系統事實 + 推薦 backend/model/compute + reason，exit 0，不需音訊。驗證：執行斷言輸出片段與 exit 0。
- [x] 6.3 實作 recommend command emits JSON only。行為：`bestasr recommend <audio>` stdout 僅一個 JSON 物件、不轉錄。驗證：`json.loads(stdout)` 成功且含必要鍵。
- [x] 6.4 實作 transcribe command with options（`--profile` / `--backend` / `--model` / `--language` / `--format` / `--output`，預設 txt 與衍生輸出路徑）。行為：`--format srt` 寫出 SRT；省略時預設 balanced/txt/auto。驗證：兩情境檔案輸出測試。
- [x] 6.5 實作 explain mode surfaces reasoning。行為：`--explain` 額外輸出 reason/warnings，且不污染轉錄輸出檔。驗證：斷言輸出檔僅含逐字稿、reason 另行呈現。
- [x] 6.6 實作 list-backends and list-models。行為：list-backends 列每個 backend 的可用性、list-models 列模型大小。驗證：執行斷言列出項目與可用性。
- [x] 6.7 實作 Non-zero exit on failure（缺檔 / 不支援格式 / 無可用 backend）。行為：對應情境印清楚訊息並非零 exit。驗證：缺檔情境斷言 exit code 非零。
- [x] 6.8 撰寫 README + examples（`examples/basic_transcribe.sh` / `diagnose.sh` / `recommend.sh`），強調「解釋為何選此模型」的定位。行為：README 含 quick start 與可解釋性說明、examples 可執行。驗證：內容審閱 + 手動執行 examples。
