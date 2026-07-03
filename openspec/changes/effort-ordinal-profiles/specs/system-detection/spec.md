# system-detection — delta

## ADDED Requirements

### Requirement: Detect dynamic machine conditions

The system SHALL expose the host's current dynamic conditions — thermal state and Low Power Mode — as a probe readable at selection time, with the provider injectable for tests. Thermal states of serious or critical, or Low Power Mode being enabled, SHALL count as machine pressure. A probe failure SHALL degrade to "no pressure" and SHALL never block or abort a transcription.

#### Scenario: Nominal machine reports no pressure

- **WHEN** the thermal state is nominal and Low Power Mode is off
- **THEN** the dynamic conditions report no pressure

#### Scenario: Thermal pressure counts

- **WHEN** the thermal state is serious or critical
- **THEN** the dynamic conditions report pressure with the thermal state as the cause

#### Scenario: Low Power Mode counts

- **WHEN** Low Power Mode is enabled
- **THEN** the dynamic conditions report pressure with Low Power Mode as the cause

#### Scenario: Probe failure degrades to no pressure

- **WHEN** the dynamic-conditions provider fails or is unavailable
- **THEN** selection proceeds as if there were no pressure
