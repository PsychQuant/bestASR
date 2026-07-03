# system-detection — delta

## ADDED Requirements

### Requirement: Detect dynamic machine conditions

The system SHALL expose the host's current dynamic conditions — thermal state and Low Power Mode — as a value readable at selection time, with the provider injectable for tests. Thermal states of serious or critical, or Low Power Mode being enabled, SHALL count as machine pressure. The value carries a designated no-pressure default that a provider SHALL yield when it cannot determine the conditions. Because the conditions are a pure synchronous value with no I/O, reading them SHALL NOT block or abort a transcription.

#### Scenario: Nominal machine reports no pressure

- **WHEN** the thermal state is nominal and Low Power Mode is off
- **THEN** the dynamic conditions report no pressure

#### Scenario: Thermal pressure counts

- **WHEN** the thermal state is serious or critical
- **THEN** the dynamic conditions report pressure with the thermal state as the cause

#### Scenario: Low Power Mode counts

- **WHEN** Low Power Mode is enabled
- **THEN** the dynamic conditions report pressure with Low Power Mode as the cause

#### Scenario: The no-pressure default yields no pressure

- **WHEN** the provider yields the designated no-pressure default (its value when conditions cannot be determined)
- **THEN** selection proceeds as if there were no pressure
