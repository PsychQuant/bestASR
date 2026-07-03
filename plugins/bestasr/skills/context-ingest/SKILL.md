---
name: context-ingest
description: 把任意格式的領域文件（pdf/docx/txt/md/圖片…）蒸餾成 bestASR 的 context.json（terms/names/phrases），寫入 context 資料夾供轉錄時的 prompt biasing 與事後校對使用。當使用者提到「整理 context」「把文件變成 context」「準備 ASR 術語」「ingest 文件」「更新 bestasr context」時使用。
---

# context-ingest — 文件 → context.json

把使用者的領域文件蒸餾成 **schema 合法的 `context.json`**（bestASR core 與 `srt-proofread` 的共同契約）。你（agent）的多模態讀檔能力就是 parser——bestASR core 只讀 context.json 與純詞表，pdf/docx 一律由本 skill 轉換。

## 目標資料夾（與 core 同三層解析，first-hit wins）

1. 使用者明講的路徑（等同 `--context-dir`）
2. 工作目錄的 `./bestasr-context/`
3. 全域 `~/.bestasr/context/`

沒有任何一層存在時，詢問使用者要建在哪層（預設建 `./bestasr-context/`）。

## 步驟

1. **讀源文件**：資料夾內（或使用者指定的）pdf / docx / pptx / txt / md / 圖片，用你自己的讀檔能力全部讀過。
2. **蒸餾三類值**（去重、保留原文寫法）：
   - `terms` — 領域術語、產品名、技術詞（ASR 最常錯的目標）
   - `names` — 人名，含 `aliases`（暱稱、英文名、常見誤聽寫法**不要**放這裡——誤聽由 proofread 處理）與 `role`（主持人/講者/與會者…，供 SRT speaker 軸對齊）
   - `phrases` — 會整句出現的慣用語、口號、標題
3. **寫 `context.json`（version 1，schema 如下）**到目標資料夾：

```json
{
  "version": 1,
  "language": "zh",
  "terms": ["benchmark-driven", "CoreML"],
  "names": [{ "name": "鄭澈", "aliases": ["Che"], "role": "主持人" }],
  "phrases": ["本機語音辨識模型的智慧路由器"],
  "notes": "給 srt-proofread 的自由補充（不會進 prompt）"
}
```

4. **自驗（完成前必做）**：
   - [ ] `version` 為 `1`
   - [ ] JSON 可被 parse（用 `python3 -c "import json;json.load(open('context.json'))"` 或等價方式驗證）
   - [ ] `names[]` 每項至少有 `name`；`aliases`/`role` 選填
   - [ ] 高價值詞在前——bestASR 的 prompt 預算約 200 tokens，超出的**依 names → terms → phrases 優先序**截斷，所以每類內部把最重要的排前面
   - [ ] `notes` 只放給校對 agent 的補充脈絡，不放詞彙（它不進 prompt）
5. **回報**：寫入路徑、各類值數量、建議下一步（`bestasr transcribe <audio> --explain` 檢查注入；`bestasr benchmark --context-dir` 量測 delta）。

## 鐵律

- **只寫 context.json，不動源文件**。
- **`voices/` 是禁區（#26）**：資料夾內是說話人 enrollment 聲紋樣本——敏感生物特徵。此 skill **絕不**讀取、處理、上傳、commit、或以任何形式將 `voices/` 內容或其 embedding 送離本機（等同 raw 第三方逐字內容的處置）。voices/ 只由 core 的 `--diarize` 在本機消費。
- **不虛構**：每個 term/name 都要能指回某份源文件；不確定的寧可不收。
- 大量文件時先挑「會在音檔中被念出來」的詞——context 是給 ASR 的，不是索引。
