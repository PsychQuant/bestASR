## 0. Design traceability

- D1 — 聚合在 Router、不在 Ranking → tasks 1.1, 1.2
- D2 — mean 等權聚合，合成代表記錄 → tasks 1.1, 1.2
- D3 — 品質門檻 0.5 只擋自主推薦 → tasks 1.1, 1.2

## 1. 聚合＋門檻（TDD）

- [x] 1.1 (design D1/D2/D3; spec asr-routing "Rank candidates by measured benchmark data") RED：RouterTests——單筆 0.0 vs 多筆 mean 更優（聚合勝）、mean>0.5 剔除（次優被薦）、全剔除落 cold-start、鎖定繞過門檻＋品質警告、reason 揭露聚合基數。先紅
- [x] 1.2 GREEN：Router.recommend usable→聚合→門檻→rank。驗證：全套件綠

## 2. 復驗＋收尾

- [x] 2.1 live 復驗（現有 store）：`recommend zh` → fluid-sensevoice；`recommend en` → whisperkit large-v3-turbo。驗證：兩者皆中
- [x] 2.2 CHANGELOG（bug fix 條目指向 #64）。驗證：條目存在
