## Context

#14 裁決：grid 全建／先跑最好、BCNF+JSON 紀錄、三 profile 沿用、en/zh/ja 先行。機上環境：Python 3.13.5、uv 0.8.22、ffmpeg 有、mlx_audio 未裝。既有架構：Engine protocol（template method）、CreateOnceStore（#7）、BenchmarkCache 單檔 upsert、Router 兩層（measured → cold-start）。

## Goals / Non-Goals

Goals：第三 backend 端到端可量測（≥1 家族真實煙測）；BCNF 四表取代扁平快取且既有查詢全數等價重建；grid 15 家族全枚舉；en 標準語料腳本化、zh/ja 可註冊。Non-goals 見 proposal。

## Decisions

### D1 — Worker 協定（persistent JSON-lines）

`mlx_worker.py`（隨 repo 出貨，venv python 執行）：啟動參數 `--model <hf_repo> [--revision <40-hex sha>]`（#15：pin 經 mlx-audio 原生 revision 透傳；worker 對非 40-hex pin fail-closed）；stdin 每行一個 request JSON `{"id":n,"audio":"/abs/path","language":"en|zh|ja|null"}`；stdout 每行一個 response JSON `{"id":n,"text":"...","segments":[{"start":s,"end":e,"text":t}],"language":"..","error":null}`。啟動完成後先印 `{"ready":true,"model":"..."}`。錯誤回 `{"id":n,"error":"msg"}` 不退出。stderr 供診斷不入協定。**理由**：模型載入付在 worker 啟動（= 暖身 pass），計時 pass 純推理，符合 benchmark spec RTF 定義；免 REST 生命週期；逐行 JSON 純函式可測。

### D2 — MLXAudioEngine

`id = .mlxAudio`（BackendID 第三成員，rawValue `"mlx-audio"`）。Worker 以 `CreateOnceStore<MLXWorker>` 快取（key = hf_repo；`retainOnly` 沿用——換模型殺舊 worker：Process.terminate + store 驅逐）。`isAvailable()` = venv python 存在且 `import mlx_audio` 成功（`<venv>/bin/python -c "import mlx_audio"`，結果 process 內 memoize）。缺 venv 的錯誤訊息給確切指令：`uv venv ~/.bestasr/mlx-env && uv pip install --python ~/.bestasr/mlx-env/bin/python mlx-audio`。`transcribeRaw`：取 worker → 送 request → 讀 response → 映射 RawTranscription（segments 缺時整段 text 單 segment，start/end 用 0/duration）。TranscribeOptions.prompt：mlx-audio v1 不支援 prompt biasing → prompt 忽略並在 explain 註記（誠實）。

### D3 — BCNF 四表（`~/.bestasr/store/`）

- `machines.jsonl`：`{machine_id, chip, unified_memory_gb}`；machine_id = sha256(chip|memory) 前 12 hex。
- `models.jsonl`（grid）：`{model_id, backend, family, size, quantization, hf_repo?, languages, est_memory_gb, priority}`；model_id = `backend|family|size|quant`；candidate key 即該四元組。既有兩 backend 的現行模型一併入 grid（priority 1），保持單一目錄。
- `corpora.jsonl`：`{corpus_id, name, language, audio_sha256, reference_sha256, duration, audio_path, reference_path}`；corpus_id = sha256(audio)|前12。path 為本機事實可變、hash 為身分。
- `measurements.jsonl`：append-only `{model_id, corpus_id, machine_id, measured_at, metric_kind, error_rate, rtf, peak_memory_gb, warmup_seconds, app_version, macos_version, context_error_rate?}`。
每表一行一 JSON（JSONL）。讀取層 `BenchmarkStore`：load 全表 → `latestMeasurements()` 每 (model,corpus,machine) 取 measured_at 最大者。**BCNF 論證**：各表非鍵屬性僅依賴本表 key；OS 版本移入量測筆（時間事實）；「未量測」= grid row 無對應 measurement。

### D4 — 遷移

`BenchmarkStore.load()` 起頭檢查舊 `~/.bestasr/benchmarks.json`：存在 → 逐筆分解（chip/memory→machines、backend/model/quant→models 補 row（size=model 名、family 對映）、audio_duration+language→合成 corpus row（audio hash 不可得 → corpus_id 用 `legacy|<language>|<duration>`）、量測欄→measurements），寫四表後改名 `.bak`。一次性、冪等（.bak 後不再觸發）。

### D5 — Grid 內容（15 家族）與先行集

priority 1（先行集）：`mlx-audio|whisper|large-v3-turbo|4bit`（三 backend 同家族對照錨）、`parakeet|0.6b|default`、`qwen3-asr|small|4bit`、`moonshine|base|default`。priority 2：各家族代表中檔（canary 1b、distil-whisper large-v3、mms 1b、granite 2b、nemotron streaming、voxtral mini-3b、qwen2-audio 7b-4bit、mega-asr、qwen3-forcedaligner）。priority 3：9B/24B 級（vibevoice-9b、voxtral-small-24b）與其餘尺寸鋪滿。hf_repo 以 mlx-community 對應 repo 填入，實作時逐一核對存在性（#5 教訓：表列必須指向真實可下載資產；query 不到的留 null 並標 `unverified`）。

### D6 — Benchmark 枚舉/寫入改造

BenchmarkRunner.enumerateCandidates 改讀 grid：backend 過濾 × priority 過濾（預設 ≤1；`--all-grid` 不設限；`--models`/`--backends` 照舊）。量測結果寫 `BenchmarkStore.append(measurement)` 取代 cache.upsert；BenchmarkReport 讀 store 投影組表（欄位不變）。BenchmarkCache 保留型別但標 deprecated、只剩遷移讀取。

### D7 — Router 改讀 store

Router.recommend 的 records 來源改為 `store.latestMeasurements(machine: current, language: resolved)` join grid（取 backend/model/quant 顯示名）——Ranking 介面不變（仍吃 BenchmarkRecord 形狀的投影 struct，避免大改）；cold-start prior 沿用 grid 的 est_memory_gb。

### D8 — Corpora registry + 子命令

`bestasr corpus add <audio> <reference.srt> --language <l> [--name]`：算 hash、AudioProber 取 duration、寫 corpora.jsonl（重複 hash → 更新 path）。`bestasr corpus list`：表格。`scripts/fetch-corpora.sh`：下載 jfk.wav（whisper.cpp repo raw）與 OSR_us_000_0010（voiptroubleshooter），afconvert 16k、寫入 registry（呼叫 `bestasr corpus add`）、內嵌已知 sha256 驗證。zh/ja：使用者以 corpus add 註冊自備素材（v1 契約）。

### D9 — 測試策略

Worker 協定：Swift 端 encode/decode 純函式測試 + 假 worker（`/bin/cat` 式 echo script 或注入 transport 閉包）測 request/response 迴圈與 error row。Engine：transport 注入（protocol `WorkerTransport`）→ spy 驗證 request 內容與映射；真 venv 煙測留 apply 末段（priority-1 最小模型一次真轉錄 + 一次 benchmark）。Store：暫存目錄四表 round-trip、latest 投影、遷移（合成舊檔 → 斷言四表 + .bak）、BCNF 鍵唯一性參數化測試。Grid：全家族枚舉數、priority 過濾、hf_repo 空值標記。Corpora：add/list round-trip、hash 冪等。CLI：既有整合測試改走 store（fixture 注入路徑）。

### D10 — 風險與緩解

mlx-audio CLI/API 面與 README 有落差 → worker 用 Python API（`mlx_audio.stt` 模組）並在 apply 首個真實煙測時鎖定實際 import 面；模型 repo 命名漂移 → grid `unverified` 標記 + 錯誤訊息帶 HF 搜尋指引；Process 殭屍 → worker deinit/terminate + `retainOnly` 殺舊；JSONL 寫入部分行損毀 → 讀取跳過壞行並警告（不 abort）。

## Implementation Contract

- `MLXAudioEngine.isAvailable()` false 當 venv 缺 → `transcribe` 拋 TranscriptionError 含安裝指令；true 時 priority-1 最小模型可端到端出 Transcript（真實煙測驗收）。
- `BenchmarkStore`：`load()` 後 `models.count ≥ 30`（15 家族鋪開）；`latestMeasurements` 對重複 key 取 measured_at 最大；遷移後舊檔成 `.bak` 且四表可重建原 recommend 結果（同 backend/model/quant/language 的 errorRate/rtf 等值）。
- 既有 135 tests 全綠（Ranking/Router/Report 介面投影等價）；新測試覆蓋 D9 清單。
- `bestasr benchmark --backends mlx-audio`（venv 就緒時）掃 priority-1 並寫 measurements；`--all-grid` 放寬。
- CLI 對外旗標既有語意不變（`--models`/`--backends`/`--json`/`--context-dir`）。
