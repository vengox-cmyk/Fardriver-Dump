#!/usr/bin/env python3
"""Offline FarDriver parameter dump tool (read-only, no controller access).

Produces the same flat CSV format as the ArcDash app ("arcdash-param-csv-v1").

  python3 tool/fardriver_dump.py log2csv arcdash_diagnostic_log.txt -o dump.csv
  python3 tool/fardriver_dump.py heb2csv backup.heb -o dump.csv
  python3 tool/fardriver_dump.py diff old.heb new.csv -o diff.csv [--all]
  python3 tool/fardriver_dump.py selftest

Inputs for `diff` may be a .heb file, a CSV written by ArcDash or this tool,
or an ArcDash diagnostic log (.txt/.log). Single file, standard library only.
The parameter table below is generated from fardriver.hpp by
tool/gen_param_catalog.py; every decode is reverse-engineered ("unverified")
and raw values plus the raw block hex are always included.
"""
from __future__ import annotations

import argparse
import csv
import io
import os
import re
import sys
from decimal import ROUND_HALF_UP, Decimal

VERSION = 'fardriver_dump.py/1'
CSV_FORMAT = 'arcdash-param-csv-v1'
DIFF_FORMAT = 'arcdash-param-diff-v1'
CSV_COLUMNS = ['block', 'word_address', 'byte_offset', 'bits', 'name',
               'raw_value', 'scaled_value', 'unit', 'enum_label',
               'raw_block_hex', 'status', 'note']
DIFF_COLUMNS = ['change', 'block', 'word_address', 'byte_offset', 'bits',
                'name', 'unit', 'a_raw', 'a_value', 'a_label', 'b_raw',
                'b_value', 'b_label', 'status']

CONFIG_BLOCKS = [
    0x00, 0x06, 0x0C, 0x12, 0x18, 0x1E, 0x24, 0x2A, 0x30, 0x5D, 0x63, 0x69,
    0x7C, 0x82, 0x88, 0x8E, 0x94, 0x9A, 0xA0, 0xA6, 0xAC, 0xB2, 0xB8, 0xBE,
    0xC4, 0xCA, 0xD0,
]
# 0x5D may never be streamed by some controllers: optional, never required.
OPTIONAL_BLOCKS = [0x5D]
HEB_BLOCKS = [b for b in CONFIG_BLOCKS if b not in OPTIONAL_BLOCKS]
MANDATORY_BLOCKS = HEB_BLOCKS
HEB_LENGTH = 696
BLOCK_LENGTH = 12

# Rotating packet index (packet[1] & 0x3F) -> block address, from the app.
FLASH_READ_ADDR = [
    0xE2, 0xE8, 0xEE, 0x00, 0x06, 0x0C, 0x12, 0xE2, 0xE8, 0xEE, 0x18, 0x1E,
    0x24, 0x2A, 0xE2, 0xE8, 0xEE, 0x30, 0x5D, 0x63, 0x69, 0xE2, 0xE8, 0xEE,
    0x7C, 0x82, 0x88, 0x8E, 0xE2, 0xE8, 0xEE, 0x94, 0x9A, 0xA0, 0xA6, 0xE2,
    0xE8, 0xEE, 0xAC, 0xB2, 0xB8, 0xBE, 0xE2, 0xE8, 0xEE, 0xC4, 0xCA, 0xD0,
    0xE2, 0xE8, 0xEE, 0xD6, 0xDC, 0xF4, 0xFA,
]

# Row layout: block, name, byteOffset, bitOffset, bitWidth, signed, kind,
#             factor, offset, unit, labels, note, status
# BEGIN GENERATED CATALOG (tool/gen_param_catalog.py)
CATALOG = [
    [0, 'VolCoeff', 0, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [0, 'Voltage2Coeff', 2, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [0, 'PhaseACoeff', 4, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [0, 'LineCoeff', 6, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [0, 'PhaseCCoeff', 8, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [0, 'SaveNum', 10, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'Arg2', 0, 0, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'AntiTheftPulse', 0, 1, 2, False, 'enum', 1.0, 0.0, '', {'0': 'Invalid', '1': 'Type1', '2': 'Type2', '3': 'Type3'}, 'PulseFD', 'unverified'],
    [6, 'unk02a', 0, 3, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [6, 'Protocol485', 0, 4, 4, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'MorseCode', 1, 0, 7, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'unk06b', 1, 7, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [6, 'SpeedKI', 2, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'SppedKP', 3, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'ThrottleLow', 4, 0, 8, False, 'int', 0.05, 0.0, 'V', {}, '/ 20', 'unverified'],
    [6, 'ThrottleHigh', 5, 0, 8, False, 'int', 0.05, 0.0, 'V', {}, '/ 20', 'unverified'],
    [6, 'FAIF', 6, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'CurveTime', 8, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'BrakeConfig', 10, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'StopWhenGround', '1': 'StopWhenFloat', '2': 'P_StopGnd', '3': 'P_StopFloat', '4': 'BrakeDisabled'}, '', 'unverified'],
    [6, 'TempSensor', 10, 4, 3, False, 'enum', 1.0, 0.0, '', {'0': 'NoTempSensor', '1': 'PTC', '2': 'NTC230K', '3': 'KTY84_130', '4': 'CACU', '5': 'KTY83_122', '6': 'NTC10K', '7': 'NTC100K'}, 'NTC_PTC, Send(0x11, 0x01)', 'unverified'],
    [6, 'PhaseExchange', 10, 7, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [6, 'SlowDown', 11, 0, 3, False, 'int', 1.0, 0.0, '', {}, '0x07', 'unverified'],
    [6, 'PC13Config', 11, 3, 1, False, 'int', 1.0, 0.0, '', {}, 'RaceResponse 0x08', 'unverified'],
    [6, 'CurrAntiTheft', 11, 4, 1, False, 'int', 1.0, 0.0, '', {}, '0x10', 'unverified'],
    [6, 'ParkConfig', 11, 5, 2, False, 'enum', 1.0, 0.0, '', {'0': 'ReversePark', '1': 'SwitchPark', '2': 'SlowDownPark', '3': 'ParkDisabled'}, '0x60', 'unverified'],
    [6, 'Direction', 11, 7, 1, False, 'int', 1.0, 0.0, '', {}, 'Send(0x12, 0x07) 0x80', 'unverified'],
    [12, 'PhaseOffset', 0, 0, 16, True, 'int', 0.1, 0.0, '', {}, '/ 10.0, Send(0x0A, 0x07)', 'unverified'],
    [12, 'ZeroBattCoeff', 2, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [12, 'FullBattCoeff', 4, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [12, 'StartKI', 6, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [12, 'MidKI', 7, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [12, 'MaxKI', 8, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [12, 'StartKP', 9, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [12, 'MidKP', 10, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [12, 'MaxKP', 11, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [18, 'LD', 0, 0, 16, True, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [18, 'AlarmDelay', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, '0x13', 'unverified'],
    [18, 'PolePairs', 4, 0, 8, False, 'int', 1.0, 0.0, '', {}, '0x14, Send(0x12, 0x01)', 'unverified'],
    [18, 'unk14b', 5, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'alway_s sent 0x59?', 'unknown'],
    [18, 'MaxSpeed', 6, 0, 16, False, 'int', 1.0, 0.0, 'rpm', {}, '0x15, Send(0x12, 0x02)', 'unverified'],
    [18, 'RatedPower', 8, 0, 16, False, 'int', 1.0, 0.0, 'W', {}, '0x16, Send(0x12, 0x03)', 'unverified'],
    [18, 'RatedVoltage', 10, 0, 16, False, 'int', 0.1, 0.0, 'V', {}, '0x17 / 10, Send(0x12, 0x04)', 'unverified'],
    [24, 'RatedSpeed', 0, 0, 16, False, 'int', 1.0, 0.0, 'rpm', {}, 'Send(0x12, 0x05)', 'unverified'],
    [24, 'MaxLineCurr', 2, 0, 16, False, 'int', 0.25, 0.0, 'A', {}, '/ 4, Send(0x12, 0x1B)', 'unverified'],
    [24, 'FollowConfig', 4, 0, 2, False, 'enum', 1.0, 0.0, '', {'0': 'FollowEnabled', '1': 'FollowDisabled', '2': 'EABSWhenBreakValid', '3': 'EABSWhenReleaseThrottle'}, '', 'unverified'],
    [24, 'ThrottleResponse', 4, 2, 2, False, 'enum', 1.0, 0.0, '', {'0': 'Line', '1': 'Sport', '2': 'ECO'}, 'ECOConfig', 'unverified'],
    [24, 'WeakA', 4, 4, 2, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [24, 'RXD', 4, 6, 2, False, 'enum', 1.0, 0.0, '', {'0': 'AF', '1': 'OD', '2': 'PP', '3': 'AF2'}, 'B10 GPIO config, == 3 affects A12 & USART2', 'unverified'],
    [24, 'SpeedPulse', 5, 0, 5, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [24, 'GearConfig', 5, 5, 3, False, 'enum', 1.0, 0.0, '', {'0': 'DefaultN', '1': 'DefaultD', '2': 'GearConfig2', '3': 'DefaultAntiTheft', '4': 'DefaultButtonHigh', '5': 'DefaultButtonMiddle'}, '', 'unverified'],
    [24, 'LQ', 6, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [24, 'BattRatedCap', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [24, 'IntRes', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'Send(0x0F, 0x08)', 'unverified'],
    [30, 'FwReRatio', 0, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'ReverseSideStandSignal', 1, 0, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'AllowSmallCurrentSwitching', 1, 1, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'NeutralAntiSkidParking', 1, 2, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'RecordMileage', 1, 3, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'LowerMagneticBrake', 1, 4, 1, False, 'int', 1.0, 0.0, '', {}, 'Extension code Y', 'unverified'],
    [30, 'DownhillReverseOvervoltageCutoff', 1, 5, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'ShieldedGearSpeedLimit2', 1, 6, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'PD1Input', 1, 7, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'LowVolProtect', 2, 0, 16, False, 'int', 0.1, 0.0, 'V', {}, '/ 10', 'unverified'],
    [30, 'CustomCode', 4, 0, 16, False, 'text', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'BCState', 6, 0, 1, False, 'int', 1.0, 0.0, '', {}, 'Edge support, Side stand?', 'unverified'],
    [30, 'SeatEnable', 6, 1, 1, False, 'int', 1.0, 0.0, '', {}, 'Zuotong, "bucket"', 'unverified'],
    [30, 'PEnable', 6, 2, 1, False, 'int', 1.0, 0.0, '', {}, 'PGear, "P file"', 'unverified'],
    [30, 'AutoBackPEnable', 6, 3, 1, False, 'int', 1.0, 0.0, '', {}, 'AutoBackPStat', 'unverified'],
    [30, 'CruiseEnable', 6, 4, 1, False, 'int', 1.0, 0.0, '', {}, 'XHStat', 'unverified'],
    [30, 'EABSEnable', 6, 5, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'PushEnable', 6, 6, 1, False, 'int', 1.0, 0.0, '', {}, 'TuixingS, "Power implementation function", enabling cancels PEnable', 'unverified'],
    [30, 'ForceAntiTheft', 6, 7, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'OverSpeedAlarm', 7, 0, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'BrakeStillPark', 7, 1, 1, False, 'int', 1.0, 0.0, '', {}, 'ParkDisableBrake', 'unverified'],
    [30, 'RememberGear', 7, 2, 1, False, 'int', 1.0, 0.0, '', {}, 'GearRememberS', 'unverified'],
    [30, 'unk21a', 7, 3, 1, False, 'int', 1.0, 0.0, '', {}, 'default 1', 'unknown'],
    [30, 'unk21b', 7, 4, 1, False, 'int', 1.0, 0.0, '', {}, 'default 1', 'unknown'],
    [30, 'unk21c', 7, 5, 1, False, 'int', 1.0, 0.0, '', {}, 'default 0', 'unknown'],
    [30, 'BackEnable', 7, 6, 1, False, 'int', 1.0, 0.0, '', {}, 'REGear', 'unverified'],
    [30, 'RelayDelay1S', 7, 7, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'ModelYear', 8, 0, 8, False, 'int', 1.0, 2000.0, '', {}, '+ 2000', 'unverified'],
    [30, 'ModelMonth', 9, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'ModelDay', 10, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [30, 'TimeHour', 11, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [36, 'TimeMin', 0, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [36, 'TimeSecond', 1, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [36, 'HighVolProtect', 2, 0, 16, False, 'int', 0.1, 0.0, 'V', {}, '/ 10', 'unverified'],
    [36, 'CustomMaxLineCurr', 4, 0, 16, False, 'int', 0.25, 0.0, 'A', {}, '/ 4', 'unverified'],
    [36, 'CustomMaxPhaseCurr', 6, 0, 16, False, 'int', 0.25, 0.0, 'A', {}, '/ 4', 'unverified'],
    [36, 'BackSpeed', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'Send(0x11, 0x03)', 'unverified'],
    [36, 'LowSpeed', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'Send(0x11, 0x02)', 'unverified'],
    [42, 'MidSpeed', 0, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [42, 'Max_Dec', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [42, 'FreeThrottle', 4, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [42, 'unk2Cb', 5, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [42, 'MaxPhaseCurr', 6, 0, 16, False, 'int', 0.25, 0.0, 'A', {}, '/ 4, Send(0x12, 0x1A)', 'unverified'],
    [42, 'SpeedAnalog', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [42, 'Max_Acc', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [48, 'StopBackCurr', 0, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'Send(0x12, 0x18)', 'unverified'],
    [48, 'MaxBackCurr', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'Send(0x12, 0x19)', 'unverified'],
    [48, 'LowSpeedLineCurr', 4, 0, 8, False, 'int', 0.78125, 0.0, '%', {}, '', 'unverified'],
    [48, 'MidSpeedLineCurr', 5, 0, 8, False, 'int', 0.78125, 0.0, '%', {}, '', 'unverified'],
    [48, 'LowSpeedPhaseCurr', 6, 0, 8, False, 'int', 0.78125, 0.0, '%', {}, '', 'unverified'],
    [48, 'MidSppedPhaseCurr', 7, 0, 8, False, 'int', 0.78125, 0.0, '%', {}, '', 'unverified'],
    [48, 'BlockTime', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [48, 'SpdPulseNum', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [93, 'unk5D', 0, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [93, 'unk5E', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'RPM index?', 'unknown'],
    [93, 'unk5F', 4, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [93, 'unk60', 6, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [93, 'unk60b', 7, 0, 8, False, 'int', 1.0, 0.0, '', {}, "counter of some sort? assigned 'a', 'b', 'c'", 'unknown'],
    [93, 'unk61', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [93, 'unk62', 10, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'set to 0xCC when reading ADC1?', 'unknown'],
    [93, 'unk62b', 11, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [99, 'MaxLineCurr2', 0, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [99, 'MaxPhaseCurr2', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, '0x64', 'unverified'],
    [99, 'MotorDia', 4, 0, 8, False, 'int', 1.0, 0.0, '', {}, '0x65,  maybe not MotorDia - values include 4. prolly Application type', 'unverified'],
    [99, 'unk65b', 5, 0, 8, False, 'int', 1.0, 0.0, '', {}, '33, 35, 36 - MaxPhaseCurr2 multipler?', 'unknown'],
    [99, 'TempCoeff', 6, 0, 16, False, 'int', 1.0, 0.0, '', {}, '0x66', 'unverified'],
    [99, 'ProdMaxVol', 8, 0, 16, False, 'int', 0.1, 0.0, 'V', {}, '/ 10.0 67, paracnt_0', 'unverified'],
    [99, 'ISMax', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, '0x68, paracnt_1', 'unverified'],
    [105, 'PausePin', 0, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'PPin, park? NC disables this feature', 'unverified'],
    [105, 'SideStandPin', 0, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'BCPin', 'unverified'],
    [105, 'CruisePin', 1, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'XHPin', 'unverified'],
    [105, 'BoostPin', 1, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'Boost Pin', 'unverified'],
    [105, 'LowSpeedPin', 2, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'SDLPin', 'unverified'],
    [105, 'HighSpeedPin', 2, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'SDHPin', 'unverified'],
    [105, 'ReversePin', 3, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'REPin', 'unverified'],
    [105, 'ForwardPin', 3, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'FWPin', 'unverified'],
    [105, 'SwitchVolPin', 4, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'Switch Voltage Pin 7 -> C15', 'unverified'],
    [105, 'SeatPin', 4, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'ZuotongPin', 'unverified'],
    [105, 'AntiTheftPin', 5, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'FDPin, "Steel" Pin', 'unverified'],
    [105, 'ChargePin', 5, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'CHGPin', 'unverified'],
    [105, 'LmtSpeed', 6, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'LmtSpeed 6C', 'unverified'],
    [105, 'DistanceLSB', 8, 0, 16, False, 'int', 0.1, 0.0, 'km', {}, '/ 10 6D', 'unverified'],
    [105, 'ParaIndex', 10, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'ParaIndex 6E, prolly Function Code', 'unverified'],
    [105, 'SpecialCode', 11, 0, 8, False, 'text', 1.0, 0.0, '', {}, 'Y makes A11 output. X may be needed for CAN??', 'unverified'],
    [124, 'unk7Ca', 0, 0, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [124, 'WeakTime', 0, 1, 3, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [124, 'unk7Cb', 0, 4, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [124, 'QuickDown', 0, 5, 3, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [124, 'SpeedMeterConfig1', 1, 0, 1, False, 'int', 1.0, 0.0, '', {}, 'Pulse', 'unverified'],
    [124, 'SpeedMeterConfig2', 1, 1, 1, False, 'int', 1.0, 0.0, '', {}, 'IsolatedPulse', 'unverified'],
    [124, 'FastRE', 1, 2, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [124, 'SpecialWeak', 1, 3, 1, False, 'int', 1.0, 0.0, '', {}, 'DeepWeak Special', 'unverified'],
    [124, 'ZeroSwitch', 1, 4, 1, False, 'int', 1.0, 0.0, '', {}, 'SpeedSwitch Valid, marked when Control_ID recevied via CAN', 'unverified'],
    [124, 'unk7Cc', 1, 5, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [124, 'MOE', 1, 6, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [124, 'SpeedMeterConfig3', 1, 7, 1, False, 'int', 1.0, 0.0, '', {}, 'Analog', 'unverified'],
    [124, 'TotalTime', 2, 0, 32, False, 'int', 1.0, 0.0, 'min', {}, 'minutes, infoc0, wktime', 'unverified'],
    [124, 'infoc1', 6, 0, 32, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [124, 'DistanceMSB', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'this << 16 / 10, km; total km = ((DistanceMSB << 16) | DistanceLSB) / 10 (per header)', 'unverified'],
    [130, 'ThrottleVoltage', 0, 0, 16, False, 'int', 0.01, 0.0, 'V', {}, '* 0.01, 0x82', 'unverified'],
    [130, 'HighVolRestore', 2, 0, 16, False, 'int', 0.1, 0.0, 'V', {}, '/ 10.0, 0x83', 'unverified'],
    [130, 'MotorTempProtect', 4, 0, 8, False, 'int', 1.0, 0.0, '°C', {}, '0x84', 'unverified'],
    [130, 'MotorTempRestore', 5, 0, 8, False, 'int', 1.0, 0.0, '°C', {}, '', 'unverified'],
    [130, 'MosTempProtect', 6, 0, 8, False, 'int', 1.0, 0.0, '°C', {}, '0x85', 'unverified'],
    [130, 'MosTempRestore', 7, 0, 8, False, 'int', 1.0, 0.0, '°C', {}, '', 'unverified'],
    [130, 'CANConfig', 8, 0, 6, False, 'int', 1.0, 0.0, '', {}, '!= 0 -> A12 = AF_PP', 'unverified'],
    [130, 'unk86b', 8, 6, 2, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [130, 'HardwareVersion', 9, 0, 8, False, 'text', 1.0, 0.0, '', {}, 'Version0', 'unverified'],
    [130, 'SoftwareVersionMajor', 10, 0, 8, False, 'text', 1.0, 0.0, '', {}, 'Version1', 'unverified'],
    [130, 'SoftwareVersionMinor', 11, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [136, 'RatioMin', 0, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio500', 1, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio1000', 2, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio1500', 3, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio2000', 4, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio2500', 5, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio3000', 6, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio3500', 7, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio4000', 8, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio4500', 9, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio5000', 10, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [136, 'Ratio5500', 11, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'Ratio6000', 0, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'Ratio6500', 1, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'Ratio7000', 2, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'Ratio7500', 3, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'Ratio8000', 4, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'Ratio8500', 5, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'Ratio9000', 6, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'RatioMax', 7, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'nratio_0', 8, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'nratio_1', 9, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'nratio_2', 10, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [142, 'nratio_3', 11, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_4', 0, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_5', 1, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_6', 2, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_7', 3, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_8', 4, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_9', 5, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_10', 6, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_11', 7, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_12', 8, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_13', 9, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_14', 10, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [148, 'nratio_15', 11, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [154, 'nratio_16', 0, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '9A', 'unverified'],
    [154, 'nratio_17', 1, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [154, 'nratio_18', 2, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '9B', 'unverified'],
    [154, 'nratio_19', 3, 0, 8, True, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [154, 'AN', 4, 0, 4, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [154, 'AlarmRecord_1', 4, 4, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [154, 'RelayOut', 4, 5, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [154, 'EmptySpeed', 4, 6, 2, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [154, 'LM', 5, 0, 5, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [154, 'unk9Db', 5, 5, 3, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [154, 'InitVol', 6, 0, 16, True, 'int', 1.0, 0.0, '', {}, '9D', 'unverified'],
    [154, 'Stage1Curr', 8, 0, 16, True, 'int', 1.0, 0.0, '', {}, 'TurtleSpeedCurrCoeff', 'unverified'],
    [154, 'VolSelectRatio', 10, 0, 8, False, 'int', 1.0, 0.0, '', {}, '9F', 'unverified'],
    [154, 'unk9Fb', 11, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [160, 'unkA0', 0, 0, 8, False, 'int', 1.0, 0.0, '', {}, '0x88 usually?', 'unknown'],
    [160, 'SysCmd', 1, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [160, 'ModelName', 2, 0, 80, False, 'text', 1.0, 0.0, '', {}, '', 'unverified'],
    [166, 'ModelName', 0, 0, 80, False, 'text', 1.0, 0.0, '', {}, '', 'unverified'],
    [166, 'unkAB', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'where password is stored?', 'unknown'],
    [172, 'unkAC', 0, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'more password, pin states?', 'unknown'],
    [172, 'unkAD', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'phone number start1[14]', 'unknown'],
    [172, 'unkAE', 4, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'phone number start0[14]', 'unknown'],
    [172, 'unkAF', 6, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [172, 'unkB0', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [172, 'unkB1', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [178, 'unkB2', 0, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [178, 'unkB3', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [178, 'OneCommSec_0', 4, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC0 B4', 'unverified'],
    [178, 'OneCommSec_1', 5, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC1', 'unverified'],
    [178, 'OneCommSec_2', 6, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC2 B5', 'unverified'],
    [178, 'OneCommSec_3', 7, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC3', 'unverified'],
    [178, 'OneCommSec_4', 8, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC4', 'unverified'],
    [178, 'OneCommSec_5', 9, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC5', 'unverified'],
    [178, 'OneCommSec_6', 10, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC6', 'unverified'],
    [178, 'OneCommSec_7', 11, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'SEC7', 'unverified'],
    [184, 'PausePosition', 0, 0, 4, False, 'int', 1.0, 0.0, '', {}, 'PPosition', 'unverified'],
    [184, 'SideStandPosition', 0, 4, 4, False, 'int', 1.0, 0.0, '', {}, 'BCPosition', 'unverified'],
    [184, 'HBarPosition', 1, 0, 4, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [184, 'AntiTheftPosition', 1, 4, 4, False, 'int', 1.0, 0.0, '', {}, 'FDPosition', 'unverified'],
    [184, 'unkB9', 2, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [184, 'Pulse', 4, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [184, 'SQH', 5, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [184, 'OnelineCurrCoeff', 6, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'CurrentCoeff', 'unverified'],
    [184, 'BackPTime', 8, 0, 5, False, 'int', 10.0, 0.0, 's', {}, 'ReleasePTime, ReleaseToPTime, * 10, seconds', 'unverified'],
    [184, 'ReleaseToSeat', 8, 5, 3, False, 'int', 1.0, 0.0, 's', {}, 'SeatDelay, seconds', 'unverified'],
    [184, 'CANBaud', 9, 0, 2, False, 'enum', 1.0, 0.0, '', {'0': 'Baud250K', '1': 'Baud500K', '2': 'Baud1M'}, 'CanSel', 'unverified'],
    [184, 'unkBC', 9, 2, 2, False, 'int', 1.0, 0.0, '', {}, 'set by CAN processing? resets baud to 250K as well', 'unknown'],
    [184, 'PasswordStatus', 9, 4, 2, False, 'enum', 1.0, 0.0, '', {'0': 'PasswordProtected', '1': 'AlsoPasswordProtected', '2': 'NoPassword'}, '', 'unverified'],
    [184, 'unkBCb', 9, 6, 2, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [184, 'Stage1Soc', 10, 0, 8, False, 'int', 1.0, 0.0, '%', {}, '', 'unverified'],
    [184, 'Stage2Soc', 11, 0, 8, False, 'int', 1.0, 0.0, '%', {}, 'paracnt_3 : 4, LINECURR?', 'unverified'],
    [190, 'LowVolWay', 0, 0, 8, False, 'enum', 1.0, 0.0, '', {'0': 'Vol2V', '1': 'Vol4V', '2': 'Vol8V', '3': 'Vol12V', '4': 'Vol16V', '5': 'Soc5Perc', '6': 'Soc6Perc', '7': 'Soc7Perc', '8': 'Soc8Perc', '9': 'Soc9Perc', '10': 'Soc10Perc', '11': 'SOP', '12': 'Other'}, 'cfg190l, CurrLimitWay', 'unverified'],
    [190, 'unkBEb', 1, 0, 4, False, 'int', 1.0, 0.0, '', {}, '< 8 with (SpecialCode - A < 7) makes GPIOB_9 output, affects Sensor/Application type. prolly Current sensor type', 'unknown'],
    [190, 'AccCoeff', 1, 4, 4, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'BstTime', 2, 0, 16, False, 'int', 0.002, 0.0, 's', {}, '/ 500, seconds', 'unverified'],
    [190, 'BstRelease', 4, 0, 16, False, 'int', 0.002, 0.0, 's', {}, '/ 500, seconds', 'unverified'],
    [190, 'ParkTime', 6, 0, 16, False, 'int', 0.002, 0.0, 's', {}, '/ 500, seconds', 'unverified'],
    [190, 'ReverseTime', 8, 0, 6, False, 'int', 1.0, 0.0, '', {}, 'InverseTime', 'unverified'],
    [190, 'JLNationalStandardStatus', 8, 6, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'Press2ForP', 8, 7, 1, False, 'int', 1.0, 0.0, '', {}, "doesn't use D1 maybe?", 'unverified'],
    [190, 'LowMediumToHighSpeed', 9, 0, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'NoSoundPrompt', 9, 1, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'Reserved', 9, 2, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [190, 'SilenceBuzzer', 9, 3, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'EnableBackupBuzzer', 9, 4, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'DisableMotorAngleSensorRepair', 9, 5, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'AllowBrakeFaultRepair', 9, 6, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'ReverseOneLine', 9, 7, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [190, 'TorqueCoeff', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'C3', 'unverified'],
    [196, 'IdleClutchFunction', 0, 0, 1, False, 'int', 1.0, 0.0, '', {}, 'H67', 'unverified'],
    [196, 'AutomaticVoltageSwitching', 0, 1, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'ReverseNeutralForIgnition', 0, 2, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'KnobToAdjustMaximumBusBar', 0, 3, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'OneTouchRepairSwitching', 0, 4, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'SqueezeBrake2xForPark', 0, 5, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'SqueezeBrakeToReleasePark', 0, 6, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'SingleCellNoBoost', 0, 7, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'LearnVolLow', 1, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'LearnVol, VQL', 'unverified'],
    [196, 'TapForwardAndBack', 2, 0, 1, False, 'int', 1.0, 0.0, '', {}, 'H67', 'unverified'],
    [196, 'DualThrottleVoltage', 2, 1, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'CenterThrottleNeutral', 2, 2, 1, False, 'int', 1.0, 0.0, '', {}, 'H74', 'unverified'],
    [196, 'EnableOneClickRepair', 2, 3, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'EnhancedInpuSignalFiltering', 2, 4, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'UnlimitedCruiseSpeed', 2, 5, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'HallDetectionX6', 2, 6, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'NewMTPAVector', 2, 7, 1, False, 'int', 1.0, 0.0, '', {}, 'H72', 'unverified'],
    [196, 'LearnVolHigh', 3, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'LearnVoh, VQH, related to A11', 'unverified'],
    [196, 'SlowDownRpm', 4, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'ParkDiff', 'unverified'],
    [196, 'StartIs', 6, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'IsInStart', 'unverified'],
    [196, 'ThrottleInsert', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, '& 0x20 TCS', 'unverified'],
    [196, 'ExitFollowSpeed', 10, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [196, 'ReCurrRatio', 11, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [202, 'AngleLearn', 0, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [202, 'SpeedLimitPin', 1, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, '4 -> A15, 5 -> C13', 'unverified'],
    [202, 'RepairPin', 1, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'NC', '1': 'PIN24', '2': 'PIN15', '3': 'PIN5', '4': 'PIN17', '5': 'PIN14', '6': 'PIN3', '7': 'PIN8', '8': 'PB4', '9': 'PINInvalid1', '10': 'PIN2', '11': 'PIN18', '12': 'PIN9', '13': 'PD1', '14': 'PINInvalid2', '15': 'PINInvalid3'}, 'OneKeyPin', 'unverified'],
    [202, 'NoCanCnt', 2, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'CAN Detect, ms, if >= 6 then * 2 else * 500; non-linear: >= 6 -> *2 ms else *500 ms (per header)', 'unverified'],
    [202, 'SPModeConfig', 3, 0, 4, False, 'enum', 1.0, 0.0, '', {'0': 'HighOnly', '1': 'AddDec', '2': 'ButtonHighLow', '3': 'ButtonLowMid', '4': 'Button3SpeedLow', '5': 'Button3SpeedMid', '6': 'Button3SpeedHigh', '7': 'Button4SpeedLow', '8': 'Button4Speed2', '9': 'Button4Speed3', '10': 'Button4SpeedHigh', '11': 'Line3Speed', '12': 'CommGear', '13': 'CANGear', '14': 'HighLowDisabled'}, 'HighLowSpeed, SDHDs/SDLDs', 'unverified'],
    [202, 'Temp70', 3, 4, 2, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [202, 'LongBack', 3, 6, 1, False, 'int', 1.0, 0.0, '', {}, 'Push RE, toggle vs momentary?', 'unverified'],
    [202, 'ThrottleLost', 3, 7, 1, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [202, 'LearnThrottle', 4, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [202, 'SpeedLowCap', 5, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'LmtSpdMinCap', 'unverified'],
    [202, 'MidSpeedCap', 6, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'LmtSpdStartCap', 'unverified'],
    [202, 'SpeedLimitByCap', 7, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [202, 'MinSpeedCapCoeff', 8, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'LmtSpdMaxCoeff', 'unverified'],
    [202, 'ParkCoeff', 9, 0, 4, False, 'int', 1.0, 0.0, '', {}, 'SlowDownCoeff', 'unverified'],
    [202, 'BattSignal', 9, 4, 4, False, 'enum', 1.0, 0.0, '', {'0': 'OneLineComm', '1': 'SerialComm', '2': 'CAN', '3': 'LithiumBattery', '4': 'LeadAcidBattery', '5': 'LFPBattery'}, 'BatSel', 'unverified'],
    [202, 'ReIsinAcc', 10, 0, 16, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [208, 'Data0', 0, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [208, 'Data1', 1, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unknown'],
    [208, 'BMQHALL', 2, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [208, 'AVGPower', 3, 0, 8, False, 'int', 4.0, 0.0, 'Wh/km', {}, '* 4, Wh/km, DataVoltage1', 'unverified'],
    [208, 'WheelRatio', 4, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'ArcDash telemetry reads WheelRadius at byte 4 and WheelRatio at byte 5 (swapped vs fardriver.hpp); unconfirmed which is right', 'unverified'],
    [208, 'WheelRadius', 5, 0, 8, False, 'int', 1.0, 0.0, '', {}, 'see WheelRatio: ArcDash telemetry reads this at byte 4', 'unverified'],
    [208, 'AVGSpeed', 6, 0, 8, False, 'int', 1.0, 0.0, 'km/h', {}, 'km/h, DataVoltage4', 'unverified'],
    [208, 'WheelWidth', 7, 0, 8, False, 'int', 1.0, 0.0, '', {}, '', 'unverified'],
    [208, 'RateRatio', 8, 0, 16, False, 'int', 1.0, 0.0, '', {}, 'SpeedRatio', 'unverified'],
    [208, 'Idle', 10, 0, 2, False, 'enum', 1.0, 0.0, '', {'0': 'Idle0_5ms', '1': 'Idle0_9ms', '2': 'Idle1_5ms', '3': 'Idle1_9ms'}, '', 'unverified'],
    [208, 'Stop', 10, 2, 2, False, 'enum', 1.0, 0.0, '', {'0': 'Stop24ms', '1': 'Stop55ms', '2': 'Stop124ms', '3': 'Stop216ms'}, '', 'unverified'],
    [208, 'ByteOption', 10, 4, 4, False, 'int', 1.0, 0.0, '', {}, 'Byte89Sel', 'unverified'],
    [208, 'SpecialFrame', 11, 0, 8, False, 'enum', 1.0, 0.0, '', {'0': 'SpeedPulse', '1': 'ReadyLamp', '2': 'FanControl', '3': 'Reserved', '16': 'GeneralLink2', '32': 'Bluetooth_TBIT', '33': 'Bluetooth_XZ_CONTROL', '34': 'Bluetooth_XMZSBXX', '35': 'Bluetooth_XM3SPEED', '36': 'Bluetooth_M2S', '37': 'Bluetooth_CN', '48': 'InternalSEC_08', '64': 'InternalSEC_07', '80': 'InternalSEC_30', '96': 'InternalSEC_27', '112': 'InternalSEC_10', '128': 'InternalSEC_2B', '144': 'InternalSEC_05', '160': 'InternalSEC_052', '176': 'InternalSEC_25', '192': 'InternalSEC_0A', '208': 'InternalSEC_1F', '224': 'ExternalSEC', '240': 'SpecialFrames', '246': 'RS485', '249': 'NOSQH', '250': 'YJOneLine', '253': 'DYOneLine', '255': 'PIN24_SelectPulseOneLine'}, 'ESQH', 'unverified'],
]
# END GENERATED CATALOG


class Dump:
    def __init__(self, blocks, source, controller_id='', capture_time='',
                 app_version=VERSION, required=None, optional=None):
        self.blocks = dict(blocks)
        self.source = source
        self.controller_id = controller_id
        self.capture_time = capture_time
        self.app_version = app_version
        self.required = list(required if required is not None
                             else MANDATORY_BLOCKS)
        self.optional = list(optional if optional is not None
                             else OPTIONAL_BLOCKS)

    @property
    def missing(self):
        return [b for b in self.required if b not in self.blocks]

    @property
    def missing_optional(self):
        return [b for b in self.optional if b not in self.blocks]


# ---------------------------------------------------------------- decoding

def _bits(data, byte_offset, bit_offset, width):
    value = 0
    nbytes = (bit_offset + width + 7) // 8
    for i in range(nbytes):
        value |= data[byte_offset + i] << (8 * i)
    return (value >> bit_offset) & ((1 << width) - 1)


def format_scaled(raw, factor, offset):
    if factor == 1.0 and offset == int(offset):
        return str(raw + int(offset))
    value = Decimal(raw * factor + offset).quantize(Decimal('0.0001'),
                                                    rounding=ROUND_HALF_UP)
    text = format(value, 'f')
    if '.' in text:
        text = text.rstrip('0').rstrip('.')
    return '0' if text in ('-0', '') else text


def _ascii(data):
    data = bytes(data).rstrip(b'\x00')
    return ''.join(chr(c) if 0x20 <= c < 0x7F else '.' for c in data)


def decode_param(entry, data):
    (block, name, byte_off, bit_off, width, signed, kind, factor, offset,
     unit, labels, note, status) = entry
    if kind == 'text':
        chunk = data[byte_off:byte_off + width // 8]
        return {'raw': ''.join(f'{c:02X}' for c in chunk),
                'value': _ascii(chunk), 'label': ''}
    raw = _bits(data, byte_off, bit_off, width)
    if signed and raw & (1 << (width - 1)):
        raw -= 1 << width
    if kind == 'enum':
        return {'raw': str(raw), 'value': str(raw),
                'label': labels.get(str(raw), '?')}
    return {'raw': str(raw), 'value': format_scaled(raw, factor, offset),
            'label': ''}


def block_hex(data):
    return ' '.join(f'{c:02X}' for c in data)


def _common(entry):
    block, name, byte_off, bit_off, width = entry[:5]
    return [f'0x{block:02X}', f'0x{block + byte_off // 2:02X}', str(byte_off),
            f'{bit_off}-{bit_off + width - 1}', name]


# ---------------------------------------------------------------- CSV

def _writer(buf):
    return csv.writer(buf, lineterminator='\n')


def dump_to_csv(dump: Dump) -> str:
    buf = io.StringIO()
    w = _writer(buf)
    missing = dump.missing
    w.writerow(['# ArcDash FarDriver parameter dump', CSV_FORMAT])
    w.writerow(['# controller_id', dump.controller_id])
    w.writerow(['# capture_time', dump.capture_time])
    w.writerow(['# app_version', dump.app_version])
    w.writerow(['# source', dump.source])
    w.writerow(['# complete', 'no' if missing else 'yes'])
    w.writerow(['# missing_blocks', ' '.join(f'0x{b:02X}' for b in missing)])
    w.writerow(['# missing_optional_blocks',
                ' '.join(f'0x{b:02X}' for b in dump.missing_optional)])
    w.writerow(CSV_COLUMNS)
    for entry in CATALOG:
        data = dump.blocks.get(entry[0])
        if data is None:
            continue
        d = decode_param(entry, data)
        w.writerow(_common(entry) + [d['raw'], d['value'], entry[9], d['label'],
                                     block_hex(data), entry[12], entry[11]])
    return buf.getvalue()


def csv_to_dump(text: str, name='csv') -> Dump:
    meta, blocks, header = {}, {}, None
    for row in csv.reader(io.StringIO(text)):
        if not row:
            continue
        if row[0].startswith('#'):
            key = row[0].lstrip('#').strip()
            meta[key] = row[1] if len(row) > 1 else ''
            continue
        if header is None:
            header = row
            if 'raw_block_hex' not in header or 'block' not in header:
                raise ValueError('not an ArcDash parameter CSV')
            continue
        rec = dict(zip(header, row))
        block = int(rec['block'], 16)
        data = bytes.fromhex(rec['raw_block_hex'])
        if len(data) != BLOCK_LENGTH:
            raise ValueError(f'block 0x{block:02X} hex has {len(data)} bytes')
        if block in blocks and blocks[block] != data:
            raise ValueError(f'inconsistent raw hex for block 0x{block:02X}')
        blocks[block] = data
    if meta.get('ArcDash FarDriver parameter dump') != CSV_FORMAT:
        raise ValueError('missing arcdash-param-csv-v1 header')
    source = meta.get('source', '') or f'csv:{name}'
    heb = source.startswith('heb:')
    return Dump(blocks, source, meta.get('controller_id', ''),
                meta.get('capture_time', ''), meta.get('app_version', ''),
                HEB_BLOCKS if heb else MANDATORY_BLOCKS,
                [] if heb else OPTIONAL_BLOCKS)


# ---------------------------------------------------------------- inputs

def heb_to_dump(data: bytes, name='file.heb') -> Dump:
    if len(data) != HEB_LENGTH:
        raise ValueError(f'HEB must contain {HEB_LENGTH} bytes, got {len(data)}')
    blocks = {addr: data[i * BLOCK_LENGTH:(i + 1) * BLOCK_LENGTH]
              for i, addr in enumerate(HEB_BLOCKS)}
    return Dump(blocks, f'heb:{name}', required=HEB_BLOCKS, optional=[])


LOG_RE = re.compile(r'^\[(?P<ts>[^\]]+)\]\s+FRAME\s+(?P<details>.*)$')


def log_to_dump(text: str, name='log', controller_id='') -> Dump:
    """Keeps the latest 12-byte payload per config block from FRAME events."""
    blocks, last_ts = {}, ''
    for line in text.splitlines():
        m = LOG_RE.match(line.strip())
        if not m:
            continue
        details = dict(
            part.split(': ', 1) for part in m.group('details').split(' | ')
            if ': ' in part)
        hex_text = details.get('hex', '')
        try:
            packet = bytes.fromhex(hex_text)
        except ValueError:
            continue
        if len(packet) != 16 or packet[0] != 0xAA:
            continue
        index = packet[1] & 0x3F
        if index >= len(FLASH_READ_ADDR):
            continue
        address = FLASH_READ_ADDR[index]
        if address not in CONFIG_BLOCKS:
            continue
        blocks[address] = packet[2:14]
        last_ts = m.group('ts')
    return Dump(blocks, f'diaglog:{name}', controller_id, last_ts)


def load_any(path: str) -> Dump:
    name = os.path.basename(path)
    with open(path, 'rb') as fh:
        data = fh.read()
    if path.lower().endswith('.heb'):
        return heb_to_dump(data, name)
    text = data.decode('utf-8-sig', errors='replace')
    if text.startswith('# ArcDash FarDriver parameter dump') or \
            text.startswith('"# ArcDash FarDriver parameter dump'):
        return csv_to_dump(text, name)
    if '=== ArcDash Diagnose-Log ===' in text or ' FRAME ' in text:
        return log_to_dump(text, name)
    if len(data) == HEB_LENGTH:
        return heb_to_dump(data, name)
    raise ValueError(f'unrecognised input: {path}')


# ---------------------------------------------------------------- diff

def diff_rows(a: Dump, b: Dump, show_all=False):
    rows = []
    for entry in CATALOG:
        da, db = a.blocks.get(entry[0]), b.blocks.get(entry[0])
        if da is None and db is None:
            continue
        va = decode_param(entry, da) if da is not None else None
        vb = decode_param(entry, db) if db is not None else None
        if va is None:
            change = 'only_b'
        elif vb is None:
            change = 'only_a'
        else:
            change = 'same' if va['raw'] == vb['raw'] else 'changed'
        if change == 'same' and not show_all:
            continue
        e = lambda v, k: v[k] if v else ''
        c = _common(entry)
        rows.append([change] + c + [entry[9],
                     e(va, 'raw'), e(va, 'value'), e(va, 'label'),
                     e(vb, 'raw'), e(vb, 'value'), e(vb, 'label'), entry[12]])
    return rows


def diff_to_csv(a: Dump, b: Dump, show_all=False, app_version=VERSION) -> str:
    buf = io.StringIO()
    w = _writer(buf)
    w.writerow(['# ArcDash FarDriver parameter diff', DIFF_FORMAT])
    for prefix, d in (('a', a), ('b', b)):
        w.writerow([f'# {prefix}_source', d.source])
        w.writerow([f'# {prefix}_controller_id', d.controller_id])
        w.writerow([f'# {prefix}_capture_time', d.capture_time])
    w.writerow(['# app_version', app_version])
    w.writerow(['# show_all', 'yes' if show_all else 'no'])
    w.writerow(DIFF_COLUMNS)
    for row in diff_rows(a, b, show_all):
        w.writerow(row)
    return buf.getvalue()


# ---------------------------------------------------------------- CLI

def _out(text, path):
    if path and path != '-':
        with open(path, 'w', encoding='utf-8', newline='') as fh:
            fh.write(text)
        print(f'wrote {path}', file=sys.stderr)
    else:
        sys.stdout.write(text)


def _warn_missing(dump):
    if dump.missing:
        print('warning: missing blocks ' +
              ' '.join(f'0x{b:02X}' for b in dump.missing) +
              ' (dump is incomplete)', file=sys.stderr)
    if dump.missing_optional:
        print('note: optional blocks not in log: ' +
              ' '.join(f'0x{b:02X}' for b in dump.missing_optional),
              file=sys.stderr)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('log2csv', help='ArcDash diagnostic log -> CSV')
    p.add_argument('log')
    p.add_argument('-o', '--output')
    p.add_argument('--controller-id', default='')
    p = sub.add_parser('heb2csv', help='.heb backup -> CSV')
    p.add_argument('heb')
    p.add_argument('-o', '--output')
    p = sub.add_parser('diff', help='diff two dumps (.heb/.csv/log)')
    p.add_argument('a')
    p.add_argument('b')
    p.add_argument('-o', '--output')
    p.add_argument('--all', action='store_true', help='include unchanged rows')
    sub.add_parser('selftest', help='run built-in synthetic tests')
    args = ap.parse_args(argv)

    if args.cmd == 'log2csv':
        with open(args.log, encoding='utf-8', errors='replace') as fh:
            dump = log_to_dump(fh.read(), os.path.basename(args.log),
                               args.controller_id)
        _warn_missing(dump)
        _out(dump_to_csv(dump), args.output)
    elif args.cmd == 'heb2csv':
        with open(args.heb, 'rb') as fh:
            dump = heb_to_dump(fh.read(), os.path.basename(args.heb))
        _out(dump_to_csv(dump), args.output)
    elif args.cmd == 'diff':
        a, b = load_any(args.a), load_any(args.b)
        rows = diff_rows(a, b)
        print(f"{sum(r[0] == 'changed' for r in rows)} changed, "
              f"{sum(r[0].startswith('only') for r in rows)} only in one side",
              file=sys.stderr)
        _out(diff_to_csv(a, b, args.all), args.output)
    elif args.cmd == 'selftest':
        return _selftest()
    return 0


def _synthetic_heb():
    out = bytearray(HEB_LENGTH)
    for i in range(HEB_LENGTH):
        out[i] = (i * 37 + 11) & 0xFF
    return bytes(out)


def _selftest():
    heb = _synthetic_heb()
    dump = heb_to_dump(heb, 'synthetic.heb')
    text = dump_to_csv(dump)
    back = csv_to_dump(text)
    assert back.blocks == dump.blocks, 'csv roundtrip blocks'
    assert dump_to_csv(back) == text, 'csv roundtrip text'
    assert back.missing == [], back.missing
    assert diff_rows(dump, back) == [], 'identical dumps differ'
    changed = bytearray(heb)
    changed[3 * 12 + 6] ^= 0xFF  # 0x12 MaxSpeed low byte
    rows = diff_rows(dump, heb_to_dump(bytes(changed), 'changed.heb'))
    assert [r[5] for r in rows] == ['MaxSpeed'], rows
    # diagnostic log with every config block once (fake CRC bytes)
    lines = ['=== ArcDash Diagnose-Log ===']
    for index, addr in enumerate(FLASH_READ_ADDR):
        payload = dump.blocks.get(addr, bytes(range(12)))
        pkt = bytes([0xAA, index]) + bytes(payload) + b'\x00\x00'
        lines.append(f'[2026-01-01T00:00:{index:02d}.000Z] FRAME      '
                     f'address: {addr} | length: 16 | hex: {block_hex(pkt)}')
    log = log_to_dump('\n'.join(lines), 'x.txt')
    assert log.missing == [] and log.missing_optional == [], log.missing
    no5d = log_to_dump('\n'.join(l for l in lines if 'address: 93 ' not in l),
                       'y.txt')
    assert no5d.missing == [] and no5d.missing_optional == [0x5D], no5d.missing
    assert '# missing_optional_blocks,0x5D' in dump_to_csv(no5d)
    assert csv_to_dump(dump_to_csv(no5d)).missing_optional == [0x5D]
    rows = diff_rows(dump, log)
    assert all(r[0] == 'only_b' for r in rows) and rows, 'log vs heb'
    try:
        heb_to_dump(heb[:-1])
        raise AssertionError('short heb accepted')
    except ValueError:
        pass
    assert format_scaled(1, 100 / 128, 0) == '0.7813'
    assert format_scaled(5, 1, 2000) == '2005'
    print(f'selftest ok ({len(CATALOG)} parameters)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
