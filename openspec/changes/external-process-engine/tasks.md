## 0. Design traceability

- D1 — 協定：argv spawn + stdout 單一 JSON，版本欄位開路 → tasks 1.1, 1.2
- D2 — BackendID 封閉 enum + 每工具一 case，不做動態 id → task 2.1
- D3 — Containment（#20 需求清單的正面回應） → tasks 1.1, 1.2, 3.1
- D4 — grid reference rows 條件升級，路由仍 measured-only → task 2.1
- D5 — 量測可比性：RTF 誠實含 process 開銷，spec 明載語意差異 → task 3.2
- D6 — registry config 位置與 schema → tasks 1.1, 1.2

## 1. 協定核心（TDD）

- [x] 1.1 (design D1/D3/D6; spec external-engine-protocol "External adapters are invoked over a versioned JSON protocol" + "External processes are contained and time-bounded" + "External engines register through a user config") RED：ExternalEngineTests——fake adapter script（成功 JSON／非零 exit＋stderr／protocol 99 拒絕／segments 選配／timeout 終止／registry 缺 config＝unavailable／unknown id 警告忽略／command 不存在＝unavailable）。先紅
- [x] 1.2 GREEN：`ExternalProcessEngine`（Process spawn argv、timeout SIGTERM→SIGKILL、JSON decode＋protocol 驗證、TranscriptionError 映射、segments→seam 或單段全文）＋`ExternalEngineRegistry`（engines.json 載入）。驗證：全套件綠

## 2. 接線

- [x] 2.1 (design D2/D4; spec asr-routing "Rank candidates by measured benchmark data" + spec model-grid "Full-family catalog") BackendID `.mlxAudio`、isAvailable＝registry 驅動、grid mlx rows 條件枚舉、Router availableOrdered、CommandCore live()、listModels。既有「reference rows never enumerate」測試改為條件版。驗證：全套件綠＋無 registry 時行為 byte-identical

## 3. Adapter ＋ 實測

- [x] 3.1 (design D3) `adapters/mlx-audio/`：adapter script（協定 JSON 輸出）＋`setup.sh`（uv venv → `~/.bestasr/adapters/mlx-audio/`＋wrapper＋registry entry 提示）。驗證：setup 在本機跑通
- [x] 3.2 (design D5; spec external-engine-protocol "External measurements are comparable and honestly labeled") 端到端實測：一個家族對 osr-harvard-1（en）真轉錄過協定；若可行加 zh 家族對 cv-zhtw-4。數字入 issue。驗證：store 有 external row 或 transcribe 輸出正確

## 4. 收尾

- [x] 4.1 README（external engines 段：協定、setup、containment、RTF 語意）＋CHANGELOG。驗證：條目指向 #51
