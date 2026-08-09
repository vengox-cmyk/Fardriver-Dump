# Specification: FarDriver Protocol Layer Test Coverage

## Context

BikeTunes communicates with FarDriver motor controllers over BLE UART using the reverse-engineered serial protocol (see `reference/Fardriver Parameter Editing, Profiles & HEB Backup.._.docx` and `reference/Fardriver Tuning Arctic Leopard.docx`). The protocol layer — `lib/utils/crc_calculator.dart`, `lib/utils/packet_parser.dart`, `lib/services/protocol_service.dart`, and `lib/utils/unit_converter.dart` — is the safety-critical foundation for all telemetry, tuning, and future data-capture features.

The repository currently has only a placeholder test (`test/widget_test.dart`), so the protocol layer has **zero test coverage**, while the workflow requires **>80% coverage** and **test-driven development**.

## Scope

This track establishes a comprehensive unit test suite for the core protocol layer and fixes any defects the tests reveal:

- **CRC calculation** (`lib/utils/crc_calculator.dart`): `computeCRC`, `verifyCRC`, including reference vectors.
- **Packet building** (`lib/services/protocol_service.dart`): `buildWritePacket`, `buildWritePacket16`, `buildSysCmd`, `setMaxLineCurrPacket`, `setMaxSpeedPacket`, `setThrottleResponsePacket`, `kphToMaxSpeedRaw`, `verifyWriteAck`, and the `FardriverAddr`/`SysCmd` constants.
- **Packet parsing** (`lib/utils/packet_parser.dart`): `extractPackets`, `parseStatusPacket`, `readInt16LE`, `readUint16LE`, `readPhaseCurrent`, `toHexString`, and the `flashReadAddr` lookup table.
- **Telemetry decoding** (`lib/utils/packet_parser.dart` + `lib/utils/unit_converter.dart`): `extractTelemetry` for addresses 0xE2, 0xE8, 0xEE, 0xF4, 0xD6, 0xD0, 0x12, 0x18, 0x0C; plus `UnitConverter` helpers (speed conversion, power, battery percent, range).

## Out of Scope

- Bluetooth connection handling (`lib/services/bluetooth_service.dart`).
- Riverpod providers, screens, and widgets.
- Ride stats / profile persistence.
- Real hardware/device integration testing.

## Acceptance Criteria

1. Every public function in the four files above is covered by at least one passing unit test (normal, edge, and failure cases where applicable).
2. Tests use **known-good reference vectors** derived from the FarDriver protocol documentation (CRC tables from `fardriver_message.hpp` with start values a=0x3C, b=0x7F).
3. Protocol-layer coverage reaches **>80%** (measured via `flutter test --coverage`).
4. Any bugs found during test authoring are fixed with a failing-test-first (TDD) approach and documented in `plan.md`.
5. The full suite passes inside the Docker container (`make test` / `docker compose run --rm flutter flutter test`).

## Testing Approach

- Test files live in `test/` mirroring the source layout (e.g., `test/utils/crc_calculator_test.dart`, `test/services/protocol_service_test.dart`).
- Where a source function returns uninitialized/incorrect data for edge cases, tests define the *expected* behavior and implementation is fixed to match.
- No hardware mocks required — all tested functions are pure.
