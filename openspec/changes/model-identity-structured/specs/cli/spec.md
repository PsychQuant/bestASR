## MODIFIED Requirements

### Requirement: list-backends and list-models

`bestasr list-backends` SHALL list supported backends with their availability, and `bestasr list-models` SHALL list supported models. A listed model SHALL be named by its family, its size and the runtime that hosts it, in the form `family size (runtime)`. The literal string `default` SHALL NOT appear in the output as a quantization or a size.

#### Scenario: list-backends shows availability

- **WHEN** the user runs `bestasr list-backends`
- **THEN** each supported backend is listed with whether it is available on this machine

#### Scenario: A model is named by family, size and runtime

- **WHEN** the user runs `bestasr list-models`
- **THEN** each row reads `family size (runtime)`, so that the same model hosted by two runtimes is recognisable as one model

#### Scenario: A deferred quantization names its decider

- **WHEN** a listed model's quantization is decided by the runtime or by a dependency rather than by this project
- **THEN** the row states that the value is deferred and names the decider, instead of printing a placeholder
