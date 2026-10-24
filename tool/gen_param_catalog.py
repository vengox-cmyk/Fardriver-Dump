#!/usr/bin/env python3
"""Generate the FarDriver parameter catalog from fardriver.hpp.

Source of truth: reference/upstream/fardriver-controllers/fardriver.hpp
(the reverse-engineered FarDriver memory map). Only the configuration blocks
0x00-0xD0 plus 0x5D are emitted; live/status blocks (0xD6+) are skipped.

Outputs (both regenerated in place):
  lib/models/fardriver_param_catalog.g.dart   -> used by the ArcDash app
  tool/fardriver_dump.py (between GENERATED markers) -> offline CLI

Usage:  python3 tool/gen_param_catalog.py [--check]

Every decode is marked "unverified" (taken from the reverse-engineered header,
not confirmed on real hardware) or "unknown" (unk*/reserved fields). Scaling
comes from the header comments plus the explicit SCALE_OVERRIDES below.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HPP = os.path.join(ROOT, 'reference', 'upstream', 'fardriver-controllers',
                   'fardriver.hpp')
DART_OUT = os.path.join(ROOT, 'lib', 'models', 'fardriver_param_catalog.g.dart')
PY_OUT = os.path.join(ROOT, 'tool', 'fardriver_dump.py')

CONFIG_BLOCKS = [
    0x00, 0x06, 0x0C, 0x12, 0x18, 0x1E, 0x24, 0x2A, 0x30, 0x5D, 0x63, 0x69,
    0x7C, 0x82, 0x88, 0x8E, 0x94, 0x9A, 0xA0, 0xA6, 0xAC, 0xB2, 0xB8, 0xBE,
    0xC4, 0xCA, 0xD0,
]

TYPE_SIZES = {
    'uint8_t': (1, False), 'int8_t': (1, True), 'char': (1, False),
    'uint16_t': (2, False), 'int16_t': (2, True),
    'uint32_t': (4, False), 'int32_t': (4, True),
}

# name -> (factor, offset, unit). Values that are only guesses are still
# exported raw alongside, so a wrong guess never hides information.
SCALE_OVERRIDES = {
    'ThrottleLow': (1 / 20, 0, 'V'),
    'ThrottleHigh': (1 / 20, 0, 'V'),
    'PhaseOffset': (0.1, 0, ''),
    'MaxSpeed': (1, 0, 'rpm'),
    'RatedSpeed': (1, 0, 'rpm'),
    'RatedPower': (1, 0, 'W'),
    'RatedVoltage': (0.1, 0, 'V'),
    'MaxLineCurr': (0.25, 0, 'A'),
    'LowVolProtect': (0.1, 0, 'V'),
    'HighVolProtect': (0.1, 0, 'V'),
    'HighVolRestore': (0.1, 0, 'V'),
    'CustomMaxLineCurr': (0.25, 0, 'A'),
    'CustomMaxPhaseCurr': (0.25, 0, 'A'),
    'MaxPhaseCurr': (0.25, 0, 'A'),
    'LowSpeedLineCurr': (100 / 128, 0, '%'),
    'MidSpeedLineCurr': (100 / 128, 0, '%'),
    'LowSpeedPhaseCurr': (100 / 128, 0, '%'),
    'MidSppedPhaseCurr': (100 / 128, 0, '%'),
    'ProdMaxVol': (0.1, 0, 'V'),
    'DistanceLSB': (0.1, 0, 'km'),
    'DistanceMSB': (1, 0, ''),  # "this << 16 / 10" - combine with LSB manually
    'TotalTime': (1, 0, 'min'),
    'ThrottleVoltage': (0.01, 0, 'V'),
    'MotorTempProtect': (1, 0, '°C'),
    'MotorTempRestore': (1, 0, '°C'),
    'MosTempProtect': (1, 0, '°C'),
    'MosTempRestore': (1, 0, '°C'),
    'BackPTime': (10, 0, 's'),
    'ReleaseToSeat': (1, 0, 's'),
    'BstTime': (1 / 500, 0, 's'),
    'BstRelease': (1 / 500, 0, 's'),
    'ParkTime': (1 / 500, 0, 's'),
    'ModelYear': (1, 2000, ''),
    'AVGPower': (4, 0, 'Wh/km'),
    'AVGSpeed': (1, 0, 'km/h'),
    'Stage1Soc': (1, 0, '%'),
    'Stage2Soc': (1, 0, '%'),
    'NoCanCnt': (1, 0, ''),  # ms rule is non-linear: >=6 -> *2 else *500
    'AlarmDelay': (1, 0, ''),
}
for _r in ['RatioMin'] + [f'Ratio{n}' for n in range(500, 9001, 500)] + ['RatioMax']:
    SCALE_OVERRIDES[_r] = (1, 0, '%')
for _n in range(20):
    SCALE_OVERRIDES[f'nratio_{_n}'] = (1, 0, '%')

# Extra provenance notes appended to the header comment.
NOTE_OVERRIDES = {
    'WheelRatio': 'ArcDash telemetry reads WheelRadius at byte 4 and WheelRatio '
                  'at byte 5 (swapped vs fardriver.hpp); unconfirmed which is right',
    'WheelRadius': 'see WheelRatio: ArcDash telemetry reads this at byte 4',
    'DistanceMSB': 'total km = ((DistanceMSB << 16) | DistanceLSB) / 10 (per header)',
    'NoCanCnt': 'non-linear: >= 6 -> *2 ms else *500 ms (per header)',
}

UNKNOWN_RE = re.compile(r'^(unk|Reserved|infoc|Data[01]$)')


def _strip_ifndef(text: str) -> str:
    out, depth = [], 0
    for line in text.splitlines():
        s = line.strip()
        if s.startswith('#ifndef _010EDITOR'):
            depth += 1
            continue
        if depth and s.startswith('#endif'):
            depth -= 1
            continue
        if not depth:
            out.append(line)
    return '\n'.join(out)


def _parse_enum_body(body: str) -> dict[int, str]:
    labels, value = {}, -1
    for raw in body.splitlines():
        line = raw.split('//')[0].strip().rstrip(',')
        if not line:
            continue
        m = re.match(r'(\w+)\s*(?:=\s*(\d+))?$', line)
        if not m:
            continue
        value = int(m.group(2)) if m.group(2) else value + 1
        labels[value] = m.group(1)
    return labels


def _comment_scale(comment: str):
    m = re.match(r'^\s*/\s*(\d+(?:\.\d+)?)\b', comment) or \
        re.search(r'(?:^|,|\s)0x[0-9A-Fa-f]+\s*/\s*(\d+(?:\.\d+)?)', comment)
    if m:
        return 1 / float(m.group(1))
    m = re.match(r'^\s*\*\s*(\d+(?:\.\d+)?)\b', comment)
    if m:
        return float(m.group(1))
    return None


def parse(hpp_text: str):
    pin_enum = _parse_enum_body(
        re.search(r'enum PIN \{(.*?)\};', hpp_text, re.S).group(1))
    params = []
    for block in CONFIG_BLOCKS:
        name = f'Addr{block:02X}'
        m = re.search(r'struct ' + name + r'\s*\{(.*?)\n\}\s*addr' +
                      f'{block:02X}' + r'\s*;', hpp_text, re.S | re.I)
        if not m:
            raise SystemExit(f'struct {name} not found')
        body = _strip_ifndef(m.group(1))
        bit = 0
        # Collapse enums into single statements: "ENUM{labels} Field : n; // c"
        pos = 0
        statements = []
        enum_re = re.compile(r'enum\s+\w+\s*\{(.*?)\}\s*(\w+)\s*:\s*(\d+)\s*;([^\n]*)', re.S)
        while pos < len(body):
            em = enum_re.search(body, pos)
            chunk_end = em.start() if em else len(body)
            for line in body[pos:chunk_end].splitlines():
                statements.append(('line', line))
            if not em:
                break
            statements.append(('enum', em))
            pos = em.end()
        for kind, item in statements:
            if kind == 'enum':
                labels = _parse_enum_body(item.group(1))
                fname, width = item.group(2), int(item.group(3))
                comment = item.group(4).split('//', 1)[1].strip() if '//' in item.group(4) else ''
                params.append(_mk(block, fname, bit, width, False, 'enum',
                                  comment, labels))
                bit += width
                continue
            line = item.strip()
            if not line or line.startswith('//'):
                continue
            code, _, comment = line.partition('//')
            code, comment = code.strip(), comment.strip()
            fm = re.match(r'(PIN|u?int(?:8|16|32)_t|char)\s+(\w+)\s*(?:\[(\d+)\])?\s*(?::\s*(\d+))?\s*;$', code)
            if not fm:
                raise SystemExit(f'cannot parse in {name}: {line!r}')
            ftype, fname, count, width = fm.groups()
            if ftype == 'PIN':
                params.append(_mk(block, fname, bit, int(width), False, 'enum',
                                  comment, pin_enum))
                bit += int(width)
                continue
            size, signed = TYPE_SIZES[ftype]
            if width:
                params.append(_mk(block, fname, bit, int(width), signed,
                                  'int', comment, None))
                bit += int(width)
                continue
            if bit % 8:
                raise SystemExit(f'misaligned {fname} in {name}')
            if ftype == 'char':
                n = int(count or 1)
                params.append(_mk(block, fname, bit, 8 * n, False, 'text',
                                  comment, None))
                bit += 8 * n
                continue
            if count:
                raise SystemExit(f'unsupported array {fname}')
            params.append(_mk(block, fname, bit, 8 * size, signed, 'int',
                              comment, None))
            bit += 8 * size
        if bit != 96:
            raise SystemExit(f'{name} decodes to {bit} bits, expected 96')
    return params


def _mk(block, name, bit, width, signed, kind, comment, labels):
    factor, offset, unit = 1.0, 0.0, ''
    if name in SCALE_OVERRIDES:
        factor, offset, unit = SCALE_OVERRIDES[name]
    elif kind == 'int':
        guess = _comment_scale(comment)
        if guess is not None:
            factor = guess
    if name in NOTE_OVERRIDES:
        comment = (comment + '; ' if comment else '') + NOTE_OVERRIDES[name]
    status = 'unknown' if UNKNOWN_RE.match(name) else 'unverified'
    return {
        'block': block,
        'name': name,
        'byteOffset': bit // 8,
        'bitOffset': bit % 8,
        'bitWidth': width,
        'signed': signed,
        'kind': kind,
        'factor': float(factor),
        'offset': float(offset),
        'unit': unit,
        'labels': labels or {},
        'note': comment,
        'status': status,
    }


def _dart_str(s: str) -> str:
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


def _dart_num(x: float) -> str:
    r = repr(float(x))
    return r


def render_dart(params) -> str:
    out = [
        '// GENERATED by tool/gen_param_catalog.py from',
        '// reference/upstream/fardriver-controllers/fardriver.hpp. Do not edit.',
        '// ignore_for_file: lines_longer_than_80_chars',
        '',
        "part of 'fardriver_param_catalog.dart';",
        '',
        'const List<FardriverParamDef> _generatedParams = [',
    ]
    for p in params:
        labels = ''
        if p['labels']:
            labels = ', labels: {' + ', '.join(
                f'{k}: {_dart_str(v)}' for k, v in sorted(p['labels'].items())) + '}'
        out.append(
            '  FardriverParamDef('
            f"block: 0x{p['block']:02X}, name: {_dart_str(p['name'])}, "
            f"byteOffset: {p['byteOffset']}, bitOffset: {p['bitOffset']}, "
            f"bitWidth: {p['bitWidth']}, signed: {'true' if p['signed'] else 'false'}, "
            f"kind: FardriverParamKind.{KIND[p['kind']]}, factor: {_dart_num(p['factor'])}, "
            f"offset: {_dart_num(p['offset'])}, unit: {_dart_str(p['unit'])}, "
            f"note: {_dart_str(p['note'])}, unverified: {'false' if p['status'] == 'unknown' else 'true'}, "
            f"unknown: {'true' if p['status'] == 'unknown' else 'false'}{labels}),")
    out.append('];')
    out.append('')
    return '\n'.join(out)


def render_py(params) -> str:
    compact = [
        [p['block'], p['name'], p['byteOffset'], p['bitOffset'], p['bitWidth'],
         p['signed'], p['kind'], p['factor'], p['offset'], p['unit'],
         {str(k): v for k, v in p['labels'].items()}, p['note'], p['status']]
        for p in params
    ]
    lines = ['CATALOG = [']
    for row in compact:
        lines.append('    ' + repr(row) + ',')
    lines.append(']')
    return '\n'.join(lines)


KIND = {'int': 'int', 'enum': 'enumeration', 'text': 'text'}

BEGIN = '# BEGIN GENERATED CATALOG (tool/gen_param_catalog.py)'
END = '# END GENERATED CATALOG'


def main():
    check = '--check' in sys.argv
    with open(HPP, encoding='utf-8') as fh:
        params = parse(fh.read())
    dart = render_dart(params)
    with open(PY_OUT, encoding='utf-8') as fh:
        py = fh.read()
    if BEGIN not in py or END not in py:
        raise SystemExit('generated markers missing in fardriver_dump.py')
    head, rest = py.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    new_py = head + BEGIN + '\n' + render_py(params) + '\n' + END + tail
    if check:
        with open(DART_OUT, encoding='utf-8') as fh:
            ok = fh.read() == dart and py == new_py
        print('up to date' if ok else 'OUT OF DATE')
        sys.exit(0 if ok else 1)
    with open(DART_OUT, 'w', encoding='utf-8') as fh:
        fh.write(dart)
    with open(PY_OUT, 'w', encoding='utf-8') as fh:
        fh.write(new_py)
    print(f'{len(params)} parameters in {len(CONFIG_BLOCKS)} blocks')


if __name__ == '__main__':
    main()
