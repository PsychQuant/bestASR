# 轉錄一律顯式指定模型

## 規則

呼叫轉錄時**必須顯式寫出模型名稱**：

```bash
bestasr transcribe --backend whisperkit --model large-v3-turbo --format srt --output "$OUT" -- "$AUDIO"
```

```jsonc
// MCP
{ "audio_path": "...", "backend": "whisperkit", "model": "large-v3-turbo", "format": "srt" }
```

**不得只給 `--backend` 就送出。** backend 決定的是 runtime，模型是另一回事 —— 同一個
`whisperkit` 底下有 `tiny` / `base` / `small` / `medium` / `large-v3-turbo` / `large-v3`，
準確率與分段行為差距極大。本機量測值（兩者 backend 不同，跨 backend 比較僅供感受量級）：
`whisperkit base` **CER 17.0%**、60× realtime；`mlx-audio whisper/large-v3-turbo` **CER 0.7%**、
7.5× realtime。同一 backend 內各模型的實際差距請跑 `bestasr recommend` 看當下量測。

寫進 skill、文件範例、腳本的每一處呼叫都適用。

## 為什麼不能靠 router

router 的推薦是**建議**，不是承接。它按 profile 的加權排序選，`medium` profile 下
以速度為主 —— `base` 因為 60× realtime 被排到第一，儘管它的 CER 是本機所有候選裡最差的一檔。

更關鍵的是**選型結果不一定看得見**：

| 呼叫模式 | 選型是否揭露 |
|---|---|
| 同步 | ✅ 回傳含 `Selected whisperkit base (default) [measured] because: …` |
| **`async=true`** | ❌ 只回 `{"job_id": "…", "status": "running"}` |
| 事後 `transcribe_status` | ❌ `unknown job`（#189）|

長音檔必須用 async，於是**最需要留痕的情境反而完全沒有留痕**。產出的逐字稿無法回溯
是哪個模型轉的 —— 它是 CER 17% 還是 CER 0.7% 的產物，事後無從得知。

顯式指定把這件事從「事後查得到嗎」變成「呼叫當下就寫死在指令裡」。

## 失敗史（2026-08-25）

批次轉錄八堂中文講課錄音（各約 3 小時），只指定 `backend="whisperkit"`、用 `async=true`、
未指定 `model`。router 選了 `base`。結果：

- 七堂的時間軸塌成**30 秒固定窗格**，漏掉 11–19% 的語音（#190）
- 內容錯誤率高到「測驗第四堂」被轉成「測驗地食堂」
- 全程沒有任何錯誤訊息

四項常見的健全性檢查**全部通過**：exit 0、檔案產出、cue 數三位數、時間碼末端對齊音檔
長度。**只有拿缺口區段回頭單獨轉錄**，才發現那些「空隙」裡有整段講課內容。

診斷過程本身也繞了遠路：先誤判成並行負載（開了 issue、寫錯根因），再排除「機器忙碌」
與「連續負載」，最後才從同步呼叫的回傳訊息看到 `Selected whisperkit base`。**如果第一次
呼叫就寫死模型，這整條路都不會發生。**

## 例外（封閉列舉，只有兩類）

1. **`bestasr benchmark`** —— 它的工作就是枚舉候選並量測，指定單一模型會使它失去意義
2. **`bestasr recommend`** —— 它的輸出就是「router 會選什麼」，指定模型同樣自我矛盾

除此之外沒有第三類。**不得依性質相似類推**：「只是試跑一下」「短音檔沒差」都不是例外
—— 短音檔今天沒差，明天同一份腳本被拿去跑三小時的檔就出事，而那正是本次事故的形狀。

## 怎麼挑模型

以本機 benchmark 為準（`bestasr recommend <audio>` 會列出量測值），把它**當建議讀**，
然後把選定的名字寫進呼叫。長音檔（> 1 小時）在挑定後值得先用前 30 分鐘試轉一次，
確認 cue 密度正常（每 cue 約 4–5 秒；30 秒／cue 是分段塌陷的訊號）。

## 相關

- PsychQuant/bestASR#191 —— 本規則的立案
- PsychQuant/bestASR#190 —— `base` 長音檔分段塌陷的現象與根因
- PsychQuant/bestASR#189 —— async job 不跨連線存活，使事後查詢選型不可行
