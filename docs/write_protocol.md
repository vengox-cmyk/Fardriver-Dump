# FarDriver write protocol (FarSure 1.3)

FarSure 1.3 is the first FarSure release that changes controller settings. This
file documents exactly what it sends, where each fact comes from, and how sure
we are about it. Code: `lib/services/write/` (protocol, allowlist, service and log).

Confidence levels:
- **High**: the official app does exactly this, and our tests reproduce its bytes.
- **Medium**: decoded and shown by the official app or by fardriver.hpp, but never written by the official app.
- **Low**: inferred.

## 1. Frame format (High)

The official MotorNet6 (FarDriver Android app) `WriteAddr(data, addr, len)` sends:

```
AA  (C0 + len + 4)  addr  addr  payload (len bytes, little endian words)  crc_lo crc_hi
```

- `len` is the payload length in bytes and is even (1 to 6 words). FarSure only ever sends 1 word (8-byte frame) or the 6-byte save stamp.
- The address is a **word** address and is sent twice.
- The CRC uses the same table and init (`3C`/`7F`) as the status frames the controller streams (`CrcCalculator`).
- Test vector from the official app: `AA C6 A0 A0 88 08 C5 09`. That frame is **factory reset** (system command `0x0888` written to `0xA0`), so FarSure reproduces it only in a unit test and can never send it: `writeWord` refuses address `0xA0`.

Source: decompiled MotorNet6 `WriteAddr` / ParaPage, cross-checked against the CRC golden tests.

## 2. Word addresses (High)

Parameters arrive in 12-byte blocks (6 words). For a field at `block` with
`byteOffset`, the word address is `block + byteOffset / 2`. Fields smaller than a
word (WheelWidth, WheelRatio, WheelRadius and SpeedPulse) are written with
**read-modify-write**: the freshest copy of the block streamed by the
controller supplies the other bits, so neighbouring settings are left unchanged.

## 3. Save to flash (High)

The official app's "Save" button:
1. writes the date stamp `[year-2000, month, day, hour, min, sec]` to word `0x22`;
2. waits 10 ms;
3. writes `88 04` to the system command word `0xA0`, giving `AA C6 A0 A0 88 04 crc crc`.

Without step 3 the change is lost at power-off. FarSure always does all three steps after its writes.

## 4. Read back and verify (High)

The controller keeps streaming every configuration block. After saving, FarSure
waits (up to 12 s) until every block it touched has arrived again, then compares
each field with the value it wrote. Possible results for each field:
- verified
- MISMATCH
- not read back
- not sent

If anything other than "verified" comes back, the result screen offers **Restore**, which writes the old values.

## 5. Writable fields (hard-coded allowlist)

| Field | Word | Encoding | Range | Confidence | Gate |
|---|---|---|---|---|---|
| RateRatio (shown as "GearRatio 4.106 (RateRatio 4106)") | 0xD4 (212) | u16 = GearRatio × 1000 | 500–30000 | High | always |
| SpdPulseNum | 0x35 (53) | u16 | 1–65535 | High | always |
| SpeedPulse | 0x1A (26) high byte bits 0–4 | RMW | 1–31 | High | always |
| WheelWidth | 0xD3 (211) high byte | RMW, mm | 40–255 | High | always |
| WheelRatio | 0xD2 (210) low byte | RMW, % | 20–120 | High | always |
| WheelRadius | 0xD2 (210) high byte | RMW, inch | 4–24 | High | always |
| LowVolProtect | 0x1F (31) | u16 = V × 10 | 10–200 V | High | always |
| BattRatedCap | 0x1C (28) | u16 Ah | 20–250 | High | always |
| HighVolProtect | 0x25 (37) | u16 = V × 10 | 10–200 V | Medium | **Experimental** toggle (off by default) |
| HighVolRestore | 0x83 (131) | u16 = V × 10 | 10–200 V | Medium | **Experimental** toggle (off by default) |

The word numbers come from the MotorNet6 ParaPage and the generated parameter
catalog (`fardriver_param_catalog.g.dart`, from fardriver.hpp).
`test/write/write_service_test.dart` covers framing, the allowlist, gating, verify, restore and undo against a fake controller.

### Never written

The following are refused by name (`WriteAllowlist.isForbiddenName`), even if somebody adds them to the list:
- current limits (line, phase, boost, regen)
- phase, hall and angle settings
- PID gains (Kp, Ki, Kd)
- field weakening
- modulation
- auto-learn
- MOS settings
- pole pairs
- every system command except save (reset, factory defaults, learn)

## 6. Safety gates

Every write, restore and undo is refused unless all of these hold:
- the link is connected;
- it has been connected for at least 3 s;
- the last controller frame is under 1.5 s old;
- **rpm = 0 and speed = 0**.

The check runs again before every word. If the wheel starts turning part-way through, the write stops, saves what was already sent, and offers Restore.

Before the first frame, a **full backup dump** is saved permanently in
`backups/prewrite_backup_<controller name>_<time>.csv`. If not every mandatory
block has been read yet, nothing is written.

The review screen shows the controller name, then each field with its old and new value. One confirmation covers the whole set.

## 7. Write log and undo

Each confirmation creates `write_log/write_<time>.csv` (format `farsure-write-log-v1`) recording:
- time
- controller name (never the MAC)
- kind (write, restore or undo)
- title
- backup file
- one row per field: old and new values (raw and text), verify result and read-back value

The log is exportable from Saved files.

**Undo to backup** (write log detail) reads that write's backup and restores
**only the fields that write touched**. It goes through the same gates and review screen.

## 8. Uncertainties

- **HighVolProtect / HighVolRestore:** the address and scale are shown by the official app, but it never writes them. They stay behind the Experimental toggle. The current 121.5/119.5 V on the 88 V (24S) pack is about 5.06 V/cell, far above any lithium charge limit, so it looks like a controller default rather than a tuned value. The battery picker refuses it as a *new* value.
- **Read-back timing:** the controller streams all blocks in roughly 1–3 s, and FarSure waits up to 12 s. A weak BLE link can show "not read back" even though the write landed. Reconnect and check the parameter list.
- **Legacy code:** `ControllerNotifier.setRideMode` (written before 1.3) can write ThrottleResponse to word 0x1A without read-modify-write, so it would also zero SpeedPulse. It has **no callers** in the UI. It is not part of the allowlisted path and should be removed or ported in a later release.
- **Controller variants:** this was tested against the frame vectors and a fake link only. Confirm on the real controller using the phone checklist in the PR.
