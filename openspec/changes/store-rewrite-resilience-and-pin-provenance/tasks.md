## 1. TDD — RED

- [x] 1.1 測試：壞行經 `upsert(corpus:)` 重寫後 byte-identical 倖存 + 下次 load 仍警告
- [x] 1.2 測試：壞行經 `seed(models:)` 重寫後倖存
- [x] 1.3 測試：`MeasurementRow` 帶 `hfRevision` round-trip；legacy 行（無 `hf_revision`）decode 為 nil

## 2. GREEN — 實作

- [x] 2.1 `rewrite<T: Codable>` preserve-verbatim（D1）
- [x] 2.2 `MeasurementRow.hfRevision: String?` + CodingKey + init 預設 nil（D3）
- [x] 2.3 append 站點自 seeded models 解析 pin 寫入（D2）

## 3. 收尾

- [x] 3.1 全套件綠；`spectra validate` 綠
- [x] 3.2 runner 端 wiring 的實測佐證記為 #18 執行項（cross-issue 註記）——#18 真實 benchmark 後，whisperkit parakeet/turbo 的量測列應帶 hf_revision

## 4. Verify fixes（wf_72760c18-889）

- [x] 4.1 rewrite/loadRaw 改 byte-level（非 UTF-8 損壞 byte-identical 倖存 + load loud；檔案不可讀 → throw 不盲寫）——RED 測試先行
- [x] 4.2 seededRow(backend,size,quantization) helper：row 自帶 family+pin（修 primary-key hardcode）、in-memory as-seeded 來源（免 store 重讀）、fallback 誠實
- [x] 4.3 migration family 對齊 live 路徑（whisper-only 時代）；wholesale 註解如實化
- [x] 4.4 測試補強：非 UTF-8 保留、re-seed pin 不變、helper 單元、fixture 現實化（mlx-audio 歷史 id）
