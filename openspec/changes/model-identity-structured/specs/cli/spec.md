## MODIFIED Requirements

### Requirement: list-backends and list-models

`bestasr list-backends` SHALL list supported backends with their availability, and `bestasr list-models` SHALL list supported models. A listed model SHALL be named by its family, its size and the runtime that hosts it, in the form `family size (runtime)`.

Removing the literal `default` from that output is NOT part of this change and its requirement lives with the catalog re-key: 19 of the 37 rows still spell it, so `list-models` still prints it 19 times. Stating the prohibition here while the code prints it — and while the test that asserts it has been moved out — is the shape of defect this review has now found twice.

#### Scenario: list-backends shows availability

- **WHEN** the user runs `bestasr list-backends`
- **THEN** each supported backend is listed with whether it is available on this machine

#### Scenario: A model is named by family, size and runtime

- **WHEN** the user runs `bestasr list-models`
- **THEN** each row reads `family size (runtime)`, so that the same model hosted by two runtimes is recognisable as one model

#### Scenario: The renderer distinguishes the four quantization kinds

- **WHEN** a listed model's quantization is not applicable, deferred to a stated decider, or unrecorded
- **THEN** the row says which of those it is rather than printing one word for all of them

Note: no catalog row currently carries any of those three kinds — every row is a `named` value — so this scenario exercises the renderer, not the catalog. It becomes observable when the re-key lands.
