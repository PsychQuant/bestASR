## MODIFIED Requirements

### Requirement: Resolve the context directory by three-layer precedence

The system SHALL resolve the context directory in this order, first hit wins, no merging across layers: an explicit `--context-dir` flag; a `.bestasr/context` directory in the current working directory; a global `context` directory under the user's `.bestasr` home directory. The resolved location (or the absence of any) SHALL be stated in the recommendation reasons. A legacy `bestasr-context` directory in the current working directory SHALL NOT be resolved; it is no longer a recognized layer, and its presence alone SHALL NOT inject any context.

#### Scenario: Explicit flag wins over both fallback layers

- **WHEN** `--context-dir /tmp/ctx` is passed and both the cwd and global directories also exist
- **THEN** only `/tmp/ctx` is loaded

#### Scenario: Working-directory layer wins over the global layer

- **WHEN** no flag is passed and both `./.bestasr/context/` and the global directory exist
- **THEN** only `./.bestasr/context/` is loaded

#### Scenario: No layer present means no context

- **WHEN** no flag is passed and neither fallback directory exists
- **THEN** no context is loaded and transcription behavior is unchanged

#### Scenario: Legacy cwd directory is no longer resolved

- **WHEN** no flag is passed and only a legacy `./bestasr-context/` directory exists, with no `./.bestasr/context/` directory and no global directory
- **THEN** no context is loaded and transcription behavior is unchanged
