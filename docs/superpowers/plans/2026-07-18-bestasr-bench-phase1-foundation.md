# bestASR-bench Phase 1（資料地基）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為社群 ASR benchmark 打好資料地基——擴充 `CorpusRow` schema、定義 corpus manifest 格式與 validator，並立起 bench GitHub repo + HF dataset 與多語種子。

**Architecture:** TDD 核心在 `BestASRKit` 加四個 contribution 型別（license 白名單、manifest row、manifest validator）+ 擴充 `CorpusRow` 的社群欄位（backward-compatible optional）。infra 部分立 `PsychQuant/bestASR-bench`（GitHub，存 measurements + corpus manifest）與 HF dataset `bestasr-corpus`（存已授權音訊+參考稿），種子多語 CC0/CC-BY 片段。

**Tech Stack:** Swift 6（SwiftPM，`BestASRKit`）、Swift Testing（`import Testing` / `@Test` / `#expect`）、`gh` CLI、HuggingFace `hf` CLI。

## Global Constraints

- 測試框架一律 **Swift Testing**（`import Testing`、`@Test func \`名稱\`()`、`#expect(...)`）——不用 XCTest。
- 新 struct 一律 `Codable, Sendable, Equatable`，JSON key 用 **snake_case**（`enum CodingKeys`），public struct 給 explicit `public init`。
- `CorpusRow` 既有 rows（`corpora.jsonl`）**不得因 schema 變更而解碼失敗**——新增欄位必須 optional（沿用 `hfRevision: String?` 的 legacy 慣例）。
- 授權白名單 = `{CC0, CC-BY, CC-BY-SA, public-domain, own-consented}`，此集合是 skill 授權閘（Plan 2）與 CI（Plan 3）的**單一定義來源**。
- repo 命名：GitHub `PsychQuant/bestASR-bench`、HF dataset `bestasr-corpus`。
- 種子多語為**硬要求**：至少 en + zh（示範 #105）；來源 Common Voice（CC0）主、LibriSpeech（CC-BY）補英文長段。
- **對外/不可逆動作**（建 public repo、建 HF dataset、上傳音訊）在 infra tasks 明確標示，執行時需人監督，不自動跑。

---

### Task 1: 擴充 `CorpusRow` 社群欄位（backward-compatible）

**Files:**
- Modify: `Sources/BestASRKit/Store/StoreTables.swift:94-127`（`CorpusRow`）
- Test: `Tests/BestASRKitTests/CorpusRowContributionTests.swift`（Create）

**Interfaces:**
- Produces: `CorpusRow` 新增 optional 屬性 `referenceProvenance / license / attribution / contributor: String?`，init 尾端新增同名參數（皆 `= nil`）。

- [ ] **Step 1: 寫失敗測試**（round-trip + legacy 解碼）

```swift
// Tests/BestASRKitTests/CorpusRowContributionTests.swift
import Foundation
import Testing
@testable import BestASRKit

struct CorpusRowContributionTests {
    @Test func `New contribution fields round-trip through JSON`() throws {
        let row = CorpusRow(
            name: "cv-zh-0001", language: "zh",
            audioSHA256: String(repeating: "a", count: 64),
            referenceSHA256: String(repeating: "b", count: 64),
            duration: 4.2, audioPath: "/tmp/a.wav", referencePath: "/tmp/a.txt",
            referenceProvenance: "human-proofread-from-whisper-large-v3",
            license: "CC0", attribution: "Common Voice clip 0001", contributor: "che")
        let back = try JSONDecoder().decode(CorpusRow.self, from: try JSONEncoder().encode(row))
        #expect(back == row)
        #expect(back.license == "CC0")
        #expect(back.referenceProvenance == "human-proofread-from-whisper-large-v3")
    }

    @Test func `Legacy corpus rows without contribution fields decode with nils`() throws {
        let legacy = """
        {"corpus_id":"aaaaaaaaaaaa","name":"old","language":"en",\
        "audio_sha256":"\(String(repeating: "a", count: 64))",\
        "reference_sha256":"\(String(repeating: "b", count: 64))",\
        "duration":3.0,"audio_path":"/x.wav","reference_path":"/x.txt"}
        """
        let row = try JSONDecoder().decode(CorpusRow.self, from: Data(legacy.utf8))
        #expect(row.license == nil)
        #expect(row.attribution == nil)
        #expect(row.contributor == nil)
        #expect(row.referenceProvenance == nil)
        #expect(row.name == "old")
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CorpusRowContributionTests`
Expected: 編譯失敗（`CorpusRow` init 沒有 `referenceProvenance:` 等參數）。

- [ ] **Step 3: 實作——擴充 `CorpusRow`**

在 `StoreTables.swift` 的 `CorpusRow` 內，`referencePath` 屬性後加：

```swift
    public let referenceProvenance: String?
    public let license: String?
    public let attribution: String?
    public let contributor: String?
```

`CodingKeys` 內 `case referencePath = "reference_path"` 後加：

```swift
        case referenceProvenance = "reference_provenance"
        case license, attribution, contributor
```

init 簽名的 `referencePath: String` 後加參數，並在 body 末（`self.corpusId = ...` 前）賦值：

```swift
    public init(
        name: String, language: String, audioSHA256: String, referenceSHA256: String,
        duration: Double, audioPath: String, referencePath: String,
        referenceProvenance: String? = nil, license: String? = nil,
        attribution: String? = nil, contributor: String? = nil
    ) {
        // ... 既有賦值 ...
        self.referenceProvenance = referenceProvenance
        self.license = license
        self.attribution = attribution
        self.contributor = contributor
        self.corpusId = String(audioSHA256.prefix(12))
    }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter CorpusRowContributionTests`
Expected: PASS（2 tests）。

- [ ] **Step 5: 全測試回歸（確認沒破既有 corpus 使用處）**

Run: `swift test`
Expected: 全綠。若既有測試以 memberwise 方式建 `CorpusRow` 而斷——不會，因新參數皆有預設值。

- [ ] **Step 6: Commit**

```bash
git add Sources/BestASRKit/Store/StoreTables.swift Tests/BestASRKitTests/CorpusRowContributionTests.swift
git commit -m "feat: add community-contribution fields to CorpusRow (backward-compatible)"
```

---

### Task 2: 授權白名單 `CorpusLicense`

**Files:**
- Create: `Sources/BestASRKit/Contribution/License.swift`
- Test: `Tests/BestASRKitTests/CorpusLicenseTests.swift`

**Interfaces:**
- Produces: `enum CorpusLicense: String`（cases: `cc0/ccBy/ccBySa/publicDomain/ownConsented`）；`static func parse(_:) -> CorpusLicense?`；`static var allowed: Set<String>`。授權閘與 CI 皆消費此型別。

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/BestASRKitTests/CorpusLicenseTests.swift
import Testing
@testable import BestASRKit

struct CorpusLicenseTests {
    @Test func `Allowed licenses parse`() {
        #expect(CorpusLicense.parse("CC0") == .cc0)
        #expect(CorpusLicense.parse(" CC-BY ") == .ccBy)   // trims whitespace
        #expect(CorpusLicense.parse("own-consented") == .ownConsented)
    }
    @Test func `Unknown licenses reject`() {
        #expect(CorpusLicense.parse("MIT") == nil)
        #expect(CorpusLicense.parse("") == nil)
        #expect(CorpusLicense.parse("all-rights-reserved") == nil)
    }
    @Test func `Allowed set is the five shareable licenses`() {
        #expect(CorpusLicense.allowed == ["CC0", "CC-BY", "CC-BY-SA", "public-domain", "own-consented"])
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CorpusLicenseTests`
Expected: 編譯失敗（`CorpusLicense` 未定義）。

- [ ] **Step 3: 實作**

```swift
// Sources/BestASRKit/Contribution/License.swift
import Foundation

/// The set of licenses under which a corpus entry may be published to the
/// shared benchmark. Single source of truth for the contribution gate
/// (bench-contribute skill) and the manifest CI validator.
public enum CorpusLicense: String, CaseIterable, Codable, Sendable {
    case cc0 = "CC0"
    case ccBy = "CC-BY"
    case ccBySa = "CC-BY-SA"
    case publicDomain = "public-domain"
    case ownConsented = "own-consented"

    /// Parse a supplied license string (whitespace-trimmed); nil if not allowed.
    public static func parse(_ raw: String) -> CorpusLicense? {
        CorpusLicense(rawValue: raw.trimmingCharacters(in: .whitespaces))
    }

    public static var allowed: Set<String> { Set(allCases.map(\.rawValue)) }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter CorpusLicenseTests`
Expected: PASS（3 tests）。

- [ ] **Step 5: Commit**

```bash
git add Sources/BestASRKit/Contribution/License.swift Tests/BestASRKitTests/CorpusLicenseTests.swift
git commit -m "feat: add CorpusLicense allow-list (shared by gate + CI)"
```

---

### Task 3: Corpus manifest row 型別 + JSONL 解析

**Files:**
- Create: `Sources/BestASRKit/Contribution/CorpusManifest.swift`
- Test: `Tests/BestASRKitTests/CorpusManifestTests.swift`

**Interfaces:**
- Consumes: 無（純資料型別）。
- Produces: `struct CorpusManifestRow`（公開可分享子集，不含機器本地 path，含 `hfAudioPath/hfReferencePath` 指向 HF dataset）；`static func parseJSONL(_:) throws -> [CorpusManifestRow]`。

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/BestASRKitTests/CorpusManifestTests.swift
import Foundation
import Testing
@testable import BestASRKit

struct CorpusManifestTests {
    private func sample() -> CorpusManifestRow {
        CorpusManifestRow(
            corpusId: "abc123abc123", name: "cv-zh-0001", language: "zh",
            audioSHA256: String(repeating: "a", count: 64),
            referenceSHA256: String(repeating: "b", count: 64),
            duration: 4.2, license: "CC0", attribution: "Common Voice clip 0001",
            contributor: "che", referenceProvenance: "official",
            hfAudioPath: "audio/zh/cv-0001.wav", hfReferencePath: "reference/zh/cv-0001.txt")
    }

    @Test func `Manifest row round-trips through JSON`() throws {
        let row = sample()
        let back = try JSONDecoder().decode(CorpusManifestRow.self, from: try JSONEncoder().encode(row))
        #expect(back == row)
    }

    @Test func `parseJSONL reads rows and skips blank lines`() throws {
        let line = String(data: try JSONEncoder().encode(sample()), encoding: .utf8)!
        let jsonl = line + "\n\n" + line + "\n"   // 2 rows + a blank line
        let rows = try CorpusManifestRow.parseJSONL(jsonl)
        #expect(rows.count == 2)
        #expect(rows[0].language == "zh")
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter CorpusManifestTests`
Expected: 編譯失敗（`CorpusManifestRow` 未定義）。

- [ ] **Step 3: 實作**

```swift
// Sources/BestASRKit/Contribution/CorpusManifest.swift
import Foundation

/// One entry of the shared corpus manifest (lives in bench repo
/// `corpus/manifest.jsonl`). The public, machine-independent projection of a
/// CorpusRow: identity hashes + community metadata + pointers into the HF
/// dataset. Machine-local audio/reference paths are deliberately NOT here.
public struct CorpusManifestRow: Codable, Sendable, Equatable {
    public let corpusId: String
    public let name: String
    public let language: String
    public let audioSHA256: String
    public let referenceSHA256: String
    public let duration: Double
    public let license: String
    public let attribution: String
    public let contributor: String
    public let referenceProvenance: String
    public let hfAudioPath: String
    public let hfReferencePath: String

    enum CodingKeys: String, CodingKey {
        case corpusId = "corpus_id"
        case name, language
        case audioSHA256 = "audio_sha256"
        case referenceSHA256 = "reference_sha256"
        case duration, license, attribution, contributor
        case referenceProvenance = "reference_provenance"
        case hfAudioPath = "hf_audio_path"
        case hfReferencePath = "hf_reference_path"
    }

    public init(
        corpusId: String, name: String, language: String,
        audioSHA256: String, referenceSHA256: String, duration: Double,
        license: String, attribution: String, contributor: String,
        referenceProvenance: String, hfAudioPath: String, hfReferencePath: String
    ) {
        self.corpusId = corpusId
        self.name = name
        self.language = language
        self.audioSHA256 = audioSHA256
        self.referenceSHA256 = referenceSHA256
        self.duration = duration
        self.license = license
        self.attribution = attribution
        self.contributor = contributor
        self.referenceProvenance = referenceProvenance
        self.hfAudioPath = hfAudioPath
        self.hfReferencePath = hfReferencePath
    }

    /// Parse a JSONL manifest (one row per line; blank lines skipped).
    public static func parseJSONL(_ text: String) throws -> [CorpusManifestRow] {
        try text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return try JSONDecoder().decode(CorpusManifestRow.self, from: Data(trimmed.utf8))
        }
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter CorpusManifestTests`
Expected: PASS（2 tests）。

- [ ] **Step 5: Commit**

```bash
git add Sources/BestASRKit/Contribution/CorpusManifest.swift Tests/BestASRKitTests/CorpusManifestTests.swift
git commit -m "feat: add CorpusManifestRow type + JSONL parsing"
```

---

### Task 4: Manifest validator（CI 與 skill 共用）

**Files:**
- Create: `Sources/BestASRKit/Contribution/ManifestValidator.swift`
- Test: `Tests/BestASRKitTests/ManifestValidatorTests.swift`

**Interfaces:**
- Consumes: `CorpusManifestRow`（Task 3）、`CorpusLicense`（Task 2）。
- Produces: `struct ManifestValidationError { corpusId; reason }`；`enum ManifestValidator { static func validate(_ rows: [CorpusManifestRow]) -> [ManifestValidationError] }`。空陣列 = 通過。

- [ ] **Step 1: 寫失敗測試**

```swift
// Tests/BestASRKitTests/ManifestValidatorTests.swift
import Testing
@testable import BestASRKit

struct ManifestValidatorTests {
    private func row(id: String = "abc123abc123", license: String = "CC0",
                     attribution: String = "src", sha: String = String(repeating: "a", count: 64))
        -> CorpusManifestRow {
        CorpusManifestRow(
            corpusId: id, name: "n", language: "zh", audioSHA256: sha,
            referenceSHA256: String(repeating: "b", count: 64), duration: 1.0,
            license: license, attribution: attribution, contributor: "che",
            referenceProvenance: "official", hfAudioPath: "a", hfReferencePath: "r")
    }

    @Test func `Valid manifest passes`() {
        #expect(ManifestValidator.validate([row(), row(id: "def456def456")]).isEmpty)
    }
    @Test func `Bad license is rejected`() {
        let errs = ManifestValidator.validate([row(license: "MIT")])
        #expect(errs.contains { $0.reason.contains("license") })
    }
    @Test func `Empty attribution is rejected`() {
        #expect(ManifestValidator.validate([row(attribution: "  ")]).contains { $0.reason.contains("attribution") })
    }
    @Test func `Non-64-hex sha is rejected`() {
        #expect(ManifestValidator.validate([row(sha: "xyz")]).contains { $0.reason.contains("sha256") })
    }
    @Test func `Duplicate corpus_id is rejected`() {
        let errs = ManifestValidator.validate([row(id: "dup000dup000"), row(id: "dup000dup000")])
        #expect(errs.contains { $0.reason.contains("duplicate") })
    }
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `swift test --filter ManifestValidatorTests`
Expected: 編譯失敗（`ManifestValidator` 未定義）。

- [ ] **Step 3: 實作**

```swift
// Sources/BestASRKit/Contribution/ManifestValidator.swift
import Foundation

public struct ManifestValidationError: Equatable, Sendable {
    public let corpusId: String
    public let reason: String
    public init(corpusId: String, reason: String) {
        self.corpusId = corpusId
        self.reason = reason
    }
}

/// Mechanical manifest checks run by bench-repo CI and (defensively) by the
/// bench-contribute skill before opening a PR. Returns [] when the manifest
/// is clean.
public enum ManifestValidator {
    public static func validate(_ rows: [CorpusManifestRow]) -> [ManifestValidationError] {
        var errors: [ManifestValidationError] = []
        var seen = Set<String>()
        for row in rows {
            if CorpusLicense.parse(row.license) == nil {
                errors.append(.init(corpusId: row.corpusId,
                                    reason: "license '\(row.license)' not in allow-list"))
            }
            if row.attribution.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.init(corpusId: row.corpusId, reason: "attribution is empty"))
            }
            if !isHex64(row.audioSHA256) {
                errors.append(.init(corpusId: row.corpusId, reason: "audio_sha256 is not 64 hex chars"))
            }
            if !isHex64(row.referenceSHA256) {
                errors.append(.init(corpusId: row.corpusId, reason: "reference_sha256 is not 64 hex chars"))
            }
            if !seen.insert(row.corpusId).inserted {
                errors.append(.init(corpusId: row.corpusId, reason: "duplicate corpus_id"))
            }
        }
        return errors
    }

    static func isHex64(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { $0.isHexDigit }
    }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `swift test --filter ManifestValidatorTests`
Expected: PASS（5 tests）。

- [ ] **Step 5: Commit**

```bash
git add Sources/BestASRKit/Contribution/ManifestValidator.swift Tests/BestASRKitTests/ManifestValidatorTests.swift
git commit -m "feat: add manifest validator (license/attribution/sha/dedup)"
```

---

### Task 5（infra）: 立 bench GitHub repo 骨架

> **⚠ 對外動作**：建立 **public** repo。執行者須人監督確認，不自動跑。

**Files（在新 repo 內）:**
- Create: `README.md`、`corpus/manifest.jsonl`（空）、`measurements/.gitkeep`、`.github/workflows/.gitkeep`、`LICENSE`

- [ ] **Step 1: 建 repo**

```bash
gh repo create PsychQuant/bestASR-bench --public \
  --description "Community benchmark for Apple-silicon local ASR backends (measurements + corpus manifest)"
```

- [ ] **Step 2: 骨架 + 首 commit**

```bash
git clone https://github.com/PsychQuant/bestASR-bench.git && cd bestASR-bench
mkdir -p corpus measurements .github/workflows
: > corpus/manifest.jsonl
: > measurements/.gitkeep
: > .github/workflows/.gitkeep
printf '# bestASR-bench\n\nCommunity benchmark for Apple-silicon local ASR backends.\nSee schema in BestASRKit Contribution/ types.\n' > README.md
git add -A && git commit -m "chore: scaffold bench repo (manifest + measurements dirs)" && git push
```

- [ ] **Step 3: 驗證**

Run: `gh repo view PsychQuant/bestASR-bench --json name,visibility`
Expected: name = bestASR-bench、visibility = PUBLIC；repo 有 `corpus/manifest.jsonl`。

---

### Task 6（infra）: 建 HF dataset `bestasr-corpus`

> **⚠ 對外動作**：建立 public HF dataset。執行者須人監督；先確認 `hf auth whoami` 已登入、目標 namespace（PsychQuant HF org 或個人帳號）已確認。

- [ ] **Step 1: 建 dataset**

```bash
hf auth whoami          # 確認登入身分與可寫的 namespace
hf repo create bestasr-corpus --repo-type dataset
```

- [ ] **Step 2: 初始結構 + card**

```bash
# 在 clone 的 dataset repo 內
mkdir -p audio reference
printf '---\nlicense: cc0-1.0\ntask_categories:\n- automatic-speech-recognition\nlanguage:\n- en\n- zh\n- ja\n---\n\n# bestasr-corpus\n\nLicensed multilingual ASR corpus for the bestASR community benchmark.\nEach clip is CC0 / CC-BY / public-domain; see per-clip attribution in the\nbench repo `corpus/manifest.jsonl`.\n' > README.md
git add -A && git commit -m "chore: init bestasr-corpus dataset structure" && git push
```

- [ ] **Step 3: 驗證**

Run: `hf repo info bestasr-corpus --repo-type dataset`（或開 HF 頁面）
Expected: dataset 存在、card 顯示多語 + 授權。

---

### Task 7（infra + gate）: 多語種子 corpus + manifest（用 Task 4 validator 把關）

> **⚠ 對外動作 + 授權紀律**：只上傳 CC0/CC-BY/public-domain 片段；每片段記 attribution。

- [ ] **Step 1: 策展片段**（每語言 3–5 個，30s–2min）
  - zh-TW、ja：Mozilla Common Voice（CC0）clip + 其官方 transcript。
  - en：Common Voice（CC0）+ LibriSpeech（CC-BY）clip + transcript。
  - 每片段記：來源 clip id/URL、license、reference transcript。

- [ ] **Step 2: 算 SHA、放 HF dataset 目錄結構**

```bash
# 對每個 (audio, reference) 對：
shasum -a 256 audio.wav        # → audio_sha256
shasum -a 256 reference.txt    # → reference_sha256
# 依語言放 audio/<lang>/<name>.wav、reference/<lang>/<name>.txt
```

- [ ] **Step 3: 生 manifest.jsonl**（每片段一列，欄位對齊 `CorpusManifestRow`）

每列 JSON keys：`corpus_id`（audio_sha256 前 12）、`name`、`language`、`audio_sha256`、`reference_sha256`、`duration`、`license`、`attribution`、`contributor`、`reference_provenance`（種子多為 `official`）、`hf_audio_path`、`hf_reference_path`。

- [ ] **Step 4: 用 validator 把關（提交前必過）**

寫一個 5 行的 `swift run` 小程式或 `swift test` fixture 讀 manifest.jsonl → `CorpusManifestRow.parseJSONL` → `ManifestValidator.validate`，Expected：回傳 `[]`（無錯）。任何 license 不合/attribution 空/SHA 錯/重複 → 修正後再提交。

- [ ] **Step 5: 上傳 + 提交**

```bash
# HF dataset：push audio/ reference/
git -C bestasr-corpus add -A && git -C bestasr-corpus commit -m "data: seed multilingual corpus (en/zh/ja)" && git -C bestasr-corpus push
# bench repo：push manifest
cp manifest.jsonl bench/corpus/manifest.jsonl
git -C bench add corpus/manifest.jsonl && git -C bench commit -m "data: seed corpus manifest (en/zh/ja)" && git -C bench push
```

- [ ] **Step 6: 驗證（Phase 1 驗收 #1、#2、#8 的資料面）**
  - `CorpusManifestRow.parseJSONL(manifest)` → validator 回 `[]`。
  - HF dataset 有對應 audio/reference，SHA 與 manifest 一致。
  - 抽一列，確認 license ∈ 白名單、attribution 非空。

---

## 本 Plan 完成後的狀態（對照 spec §11）

達成 spec §11 驗收的 **#1、#2、#8 的資料/schema 面**，以及 CI（Plan 3）與指令（Plan 2）所需的 schema/validator 地基。**未涵蓋**（→ Plan 2/3）：`corpus pull` / `bench submit` / `corpus contribute` 指令、`bench-contribute` skill、CI workflow、leaderboard 生成、端到端跑通（#3–#7）。

## Self-Review 註記

- **Spec coverage**：Task 1 對應 §5 schema delta；Task 2 對應 §8.3 授權白名單；Task 3/4 對應 §4.1 manifest + §8.2 CI 驗證的核心邏輯；Task 5/6/7 對應 §4.1/§4.2/§10 infra + 種子。§6 貢獻指令、§7 skill、§8 CI workflow、leaderboard → 明確劃給 Plan 2/3。
- **Placeholder**：Task 7 的「確切片段清單」是不可化約的人工策展（授權紀律要求逐一挑），已標為 infra step 而非臆造 exact 資料；validator gate（Step 4）確保產出仍被機械把關。
- **Type consistency**：`CorpusManifestRow` 欄位在 Task 3 定義、Task 4 validator 與 Task 7 manifest 一致引用；`CorpusLicense.parse` 在 Task 2 定義、Task 4 引用；`CorpusRow` 新欄位在 Task 1 定義、Task 7 manifest 對映（manifest 是 CorpusRow 的公開投影）。
