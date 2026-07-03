# Tasks — effort-ordinal-profiles

## 1. RouterProfile 序數化（W1 core）
- [x] 1.1 tests RED：5 序數 case、權重錨點（0.267/0.5/0.8/0.9/1.0）、max=1.0
- [x] 1.2 DataModels：RouterProfile → low/medium/high/xhigh/max（GREEN）
- [x] 1.3 ModelRegistry.profileModels 5-key（high/xhigh/max 同列，D5）+ ColdStartPrior tests 更新
- [x] 1.4 Ranking 顯式 total order（D2：score desc → timesRealtime desc → 字典序）+ max 同分 tie-break tests

## 2. 動態狀態（W2）
- [x] 2.1 tests RED：DynamicHostState probe（nominal/serious/LPM/失敗降級）
- [x] 2.2 system-detection 域實作 + @Sendable seam（GREEN）

## 3. auto 解析 + CLI（W1+W2 接線）
- [x] 3.1 tests RED：auto→medium、auto+壓力→low、顯式序數不降檔、legacy 值錯誤含遷移對照、explain 揭露
- [x] 3.2 CommandCore resolveProfile（兩 parse site 收斂單一函式）+ seam 注入（GREEN）
- [x] 3.3 SelectionOptions 預設 auto、bench 預設 medium、help 文案

## 4. Docs（W3）
- [x] 4.1 README 重寫（D7 結構；diarize/voices/context/explain/benchmark 全數入文；Profiles 契約表）
- [x] 4.2 CHANGELOG（遷移對照表）

## 5. 收尾
- [x] 5.1 spectra validate + 全套件綠
- [x] 5.2 --explain live 冒煙（auto 解析理由可見）
