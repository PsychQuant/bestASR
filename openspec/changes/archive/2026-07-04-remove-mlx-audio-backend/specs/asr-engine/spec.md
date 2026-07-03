## MODIFIED Requirements

### Requirement: Availability detection is graceful

`is_available()` SHALL determine whether the underlying package and runtime are usable by probing via lazy import or an equivalent runtime probe, and SHALL return false rather than raising when the package or runtime is absent.

#### Scenario: Uninstalled backend reports unavailable

- **WHEN** `is_available()` is called for a backend whose underlying package is not installed
- **THEN** it returns false
- **AND** no ImportError propagates to the caller
