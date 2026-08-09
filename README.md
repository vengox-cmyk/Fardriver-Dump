# ArcDash

A Flutter app for read-only monitoring of FarDriver motor controllers on electric dirt bikes. It connects via Bluetooth BLE UART and implements the reverse-engineered FarDriver serial protocol.

> The current development release is read-only. Parameter writes, profile apply,
> restore, and Street-Legal switching are disabled until the hardware safety and
> read-back gates are complete.

## Features

- **Live Telemetry Dashboard** — speed, voltage, current, power, temperatures, battery %
- **Ride Stats** — session log with distance, time, avg/top speed, Wh used
- **Raw Debug Screen** — live hex packet dump with CRC verification
- **Local Dashboard Layouts** — separate portrait and landscape cockpit layouts
- **Android-first** — Android is the supported Version-1 target

## Supported Hardware

The app communicates with **FarDriver ND-series Bluetooth programming dongles** (BLE UART adapters, device names often contain "YuanQ", "FOC", or "FarDriver"). These use BLE UART service:

- Service UUID: `0000FFE0-0000-1000-8000-00805F9B34FB`
- Characteristic UUID: `0000FFE1-0000-1000-8000-00805F9B34FB`

> **Classic BT SPP note:** Some older dongles use classic Bluetooth SPP/RFCOMM. These work on Android but are **not supported on iOS** (Apple restricts classic BT to MFi-certified accessories). Use a BLE UART dongle for full cross-platform support.

## Protocol

Based on the reverse-engineered protocol from [jackhumbert/fardriver-controllers](https://github.com/jackhumbert/fardriver-controllers).

- 16-byte rotating status packets with CRC-16 (custom tables)
- Memory-mapped parameter addresses (0x00–0xFA)
- 8-byte write packets for parameter changes

## Setup

### Prerequisites

- Flutter SDK 3.2+
- Xcode 15+ (iOS / macOS)
- Android Studio / Android SDK 21+

### Quick Start

```bash
# 1. Clone the repo
git clone <repository-url>
cd ArcDash

# 2. Install dependencies
flutter pub get

# 3. Run code generation (Riverpod providers)
dart run build_runner build --delete-conflicting-outputs

# 4. Run on device
flutter run
```

### iOS Setup

`ios/Runner/Info.plist` already includes the required Bluetooth keys:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>ArcDash needs Bluetooth to connect to your FarDriver controller dongle.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>ArcDash needs Bluetooth to connect to your FarDriver controller dongle.</string>
```

### macOS Setup

`macos/Runner/DebugProfile.entitlements` and `Release.entitlements` already include:
```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

### Android Setup

Already configured in `AndroidManifest.xml`:
- `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (Android 12+)
- `ACCESS_FINE_LOCATION` (required for BLE scanning pre-Android 12)
- `minSdkVersion 21`

### Windows / Linux

- **Windows 10+**: uses WinRT Bluetooth API, no extra config needed
- **Linux**: requires BlueZ (`sudo apt install bluez`)

## Tuning Safely

> **WARNING:** Increasing current limits can overheat the motor, damage the controller, or create unsafe speeds. Always:
> 1. Test in a safe, open area
> 2. Start with small changes
> 3. Monitor motor and controller temps
> 4. Keep the "Restore Stock" option available
> 5. Comply with local laws — tuned bikes may not be legal on public roads

## Architecture

```
DongleService (flutter_blue_plus)
  └─ raw BLE bytes
      └─ PacketParser (CRC verify + address decode)
          └─ ControllerStateNotifier (Riverpod)
              ├─ Dashboard UI (live telemetry)
              ├─ TuningNotifier (parameter writes)
              └─ StatsNotifier (session logging)
```

## License

MIT
## Development APK

Jeder Push auf `main` fuehrt Tests und einen Android-Debug-Build in der
gepinnten Docker-Toolchain aus. Bei Erfolg aktualisiert GitHub Actions das
Prerelease `latest-development` und ersetzt dort
`ArcDash-development.apk` sowie die SHA-256-Datei.

Das Development-Release ist mit dem festen, oeffentlichen ArcDash-Development-
Key `android/dev-keystore.jks` signiert. Lokale Docker-Builds und GitHub-Builds
koennen sich dadurch gegenseitig als Update installieren. Beim ersten Wechsel
von einer aelteren, zufaellig signierten APK ist einmalig eine Deinstallation
notwendig; danach bleibt die Signatur stabil.

Der Development-Key ist absichtlich nicht geheim und darf niemals fuer ein
stabiles Produktionsrelease verwendet werden. Die produktive Signatur wird erst
nach dem Release-Sicherheitsgate T082 als geschuetztes GitHub Secret eingerichtet.
