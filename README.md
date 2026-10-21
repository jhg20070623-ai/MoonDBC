# MoonDBC

MoonDBC is a MoonBit library and small CLI for parsing, validating, encoding,
and decoding classic CAN DBC signal schemas. It works at the DBC message and
signal level. It does not access CAN adapters or capture bus traffic.

This is an MVP for a documented DBC subset, not a complete DBC implementation.

## Requirements and local run

Install the MoonBit toolchain, then run these commands from the project root:

```sh
moon update
moon check
moon test
moon run cmd/moondbc -- validate testdata/minimal.dbc
```

The library package is at the project root. The CLI is a separate executable
package in `cmd/moondbc`; it reads files and prints diagnostics while delegating
parsing, validation, and codec operations to the library.

## Library API

The public API provides `parse_dbc`, `validate_schema`, `decode_frame`, and
`encode_frame`. Raw signal values use a tagged `UInt64` / `Int64` representation
so raw 64-bit integers do not pass through `Double`.

```moonbit
let dbc_text = "BO_ 256 Demo: 2 ECU\n SG_ Speed : 4|12@1+ (0.5,-1) [-1|2047] \"km/h\" ECU"
let database = match @moondbc.parse_dbc(dbc_text) {
  Ok(database) => database
  Err(error) => fail("DBC parse failed at line \{error.line}: \{error.message}")
}
let frame = match
  @moondbc.decode_frame(database, 256U, Bytes::from_array([b'\xA0', b'\xBC'])) {
  Ok(frame) => frame
  Err(_) => fail("frame decode failed")
}
```

The complete runnable version is `moon run examples/api_demo`.

The raw decode API is exact. `decode_physical` returns a precision error when a
raw integer cannot be represented exactly by the current `Double` conversion
policy. Physical encoding rejects out-of-range and non-integral inverse-scale
values; it does not round or clamp.

DBC `VAL_` integer choice tables are retained in `DbcDatabase.value_descriptions`.
Use `lookup_value_label(database, message_id, signal_name, raw_value)` to map a
raw value to its label, or `lookup_raw_value(database, message_id, signal_name,
label)` for the reverse mapping. These helpers do not change raw/physical codec
behavior; malformed, duplicate, or out-of-range table entries are rejected or
reported by parsing and schema validation.

DBC `CM_` network, node, message, and signal comments are retained in
`DbcDatabase.comments`. Comment references are checked against parsed messages,
signals, and node declarations. `inspect` prints comments with quotes,
backslashes, and control characters escaped.

## CLI

All examples below run from the repository root and use project-authored
synthetic fixtures:

```sh
moon run cmd/moondbc -- validate testdata/minimal.dbc
moon run cmd/moondbc -- inspect testdata/common_header.dbc
moon run cmd/moondbc -- decode testdata/minimal.dbc --frame-id 256 --data A0BC
moon run cmd/moondbc -- encode testdata/minimal.dbc --message Minimal --signal IntelValue=3018 --signal Mode=2
moon run cmd/moondbc -- encode testdata/minimal.dbc --message Minimal --physical --signal IntelValue=1508 --signal Mode=2
```

The Intel example decodes raw `3018` and physical `1508` because its fixture
explicitly defines factor `0.5` and offset `-1`. Encoding that raw value with
`Mode=2` emits `A2BC`. `--physical` interprets assigned values as physical
quantities and applies the inverse factor/offset conversion; values that do not
map exactly to an in-range integer raw value are rejected without rounding or
clamping.

`inspect` and `decode` also support `--json`. Raw signal values are decimal
strings so all supported 64-bit integers remain exact in JSON consumers.
Physical values are JSON numbers when representable; otherwise they are `null`
with a `physical_status` explaining the precision or range limitation. Run
`python scripts/json_cli_test.py` to validate the output with Python's standard
JSON parser, including signed and unsigned 64-bit boundaries.

## Supported subset

The current implementation handles classic CAN frames with DLC 0–8, standard
and extended 29-bit message identifiers, Intel little-endian and Motorola DBC
sawtooth bit numbering, signed and unsigned integer signals, factor/offset
conversion, and schema checks for widths, ranges, overlap, and DLC bounds. DBC
extended identifiers use the DBC bit-31 marker internally; the frame CLI takes
the actual on-bus identifier and an explicit `--extended` flag. The current
parser's exact declaration handling is listed in
[`docs/support-matrix.md`](docs/support-matrix.md).

Multiplexing, floating-point signals, and attributes that can alter frame or
signal interpretation are rejected. CAN FD, ARXML, CAN hardware I/O, and
complete DBC compatibility are outside this MVP.

## Tests and independent comparison

Run the MoonBit checks and file-level CLI integration with:

```sh
moon fmt --check
moon check
moon test
moon run scripts/integration_test.mbtx
```

The MoonBit integration script launches the CLI on the DBC files under `testdata/`.
For the optional development-only comparison, install `requirements-dev.txt`
into a Python virtual environment and run the comparison with that environment's
interpreter. On Windows:

```powershell
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.venv\Scripts\python.exe scripts/cantools_compare.py
```

On Unix-like systems:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-dev.txt
python scripts/cantools_compare.py
```

Python and cantools are not used by the MoonBit library or CLI at runtime.

## Boundary with moonbit-pcap

MoonDBC interprets DBC signal definitions and converts payload bytes to/from
typed raw signal values. A packet-capture library such as moonbit-pcap handles
capture-file or packet/frame parsing. MoonDBC does not provide CAN capture,
transport, device access, or bus monitoring.

## Data and license

The source code and hand-written synthetic fixtures in this repository are
licensed under Apache-2.0; see [`LICENSE`](LICENSE). The fixtures contain no
vendor DBC data. The project does not claim licensing rights to the DBC
specification or third-party datasets. cantools is a separate development-only
reference tool with its own license.
