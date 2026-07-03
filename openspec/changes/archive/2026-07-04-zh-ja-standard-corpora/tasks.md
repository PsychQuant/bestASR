## 1. 語料供應鏈

- [x] 1.1 FLEURS live probe（gated 與否、大小、revision、格式）
- [x] 1.2 fetch-corpora.sh 延伸（pin ×3 層 + afconvert + python3 串接 + SRT 內嵌 + corpus add）
- [x] 1.3 live 跑 script 註冊 zh+ja

## 2. 實測

- [x] 2.1 zh 雙 backend benchmark
- [x] 2.2 ja 雙 backend benchmark
- [x] 2.3 `recommend --language zh|ja` 回 measured（spec scenario 驗收）— zh: measured/tiny(balanced)、ja: measured/tiny(balanced)；accurate profile 選 turbo（per-language 路由 + profile 差異皆活）

## 3. 收尾

- [x] 3.1 corpora spec ADDED delta；CHANGELOG；`spectra validate` 綠
