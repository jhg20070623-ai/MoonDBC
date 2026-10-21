"""Development-only differential checks against cantools.

All DBC snippets and frame vectors are authored in this repository. This
script is not imported by the MoonBit library and is not a runtime dependency.
Run with: .venv\\Scripts\\python.exe scripts/cantools_compare.py on Windows.
"""

import json
import subprocess
import cantools


HEADER = '''VERSION ""
NS_ :
BS_:
BU_: ECU
'''

DBC_BASE = HEADER + '''BO_ 256 IntelMsg: 2 ECU
 SG_ IntelValue : 4|12@1+ (0.5,-1) [-1|2047] "km/h" ECU
BO_ 257 MotorolaMsg: 2 ECU
 SG_ MotorolaValue : 7|12@0+ (1,0) [0|4095] "raw" ECU
BO_ 258 SignedMsg: 2 ECU
 SG_ SignedValue : 0|12@1- (1,0) [-2048|2047] "raw" ECU
BO_ 291 StandardFrame: 1 ECU
 SG_ Value : 0|8@1+ (1,0) [0|255] "" ECU
BO_ 2147483939 ExtendedFrame: 1 ECU
 SG_ Value : 0|8@1+ (1,0) [0|255] "" ECU
'''

MOTOROLA_WIDTHS = [1, 7, 8, 9, 12, 16, 32, 63, 64]


def build_dbc() -> str:
    lines = [DBC_BASE]
    for index, width in enumerate(MOTOROLA_WIDTHS):
        unsigned_max = (1 << width) - 1
        signed_min = -(1 << (width - 1))
        signed_max = (1 << (width - 1)) - 1
        unsigned_id = 300 + index * 2
        signed_id = unsigned_id + 1
        lines.extend(
            [
                f"BO_ {unsigned_id} MotorolaU{width}: 8 ECU\n",
                f' SG_ Value : 7|{width}@0+ (1,0) [0|{unsigned_max}] "" ECU\n',
                f"BO_ {signed_id} MotorolaS{width}: 8 ECU\n",
                f' SG_ Value : 7|{width}@0- (1,0) [{signed_min}|{signed_max}] "" ECU\n',
            ]
        )
    return "".join(lines)


def check(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    print(f"PASS {label}")


def main() -> None:
    database = cantools.database.load_string(build_dbc(), database_format="dbc")
    intel = database.get_message_by_frame_id(256)
    motorola = database.get_message_by_frame_id(257)
    signed = database.get_message_by_frame_id(258)
    standard_frame = database.get_message_by_name("StandardFrame")
    extended_frame = database.get_message_by_name("ExtendedFrame")
    moonbit_run = subprocess.run(
        ["moon", "run", "cmd/vectors"],
        check=True,
        capture_output=True,
        text=True,
    )
    moonbit = dict(line.split("=", 1) for line in moonbit_run.stdout.splitlines() if "=" in line)
    passed = 0
    results: list[bool] = []

    def check(condition: bool, label: str) -> None:
        nonlocal passed
        results.append(condition)
        if not condition:
            raise AssertionError(label)
        print(f"PASS {label}")
        if label.startswith("cantools ") or "MoonBit/cantools agree" in label:
            passed += 1

    def cross_check(name: str, cantools_value: int | float | str) -> None:
        nonlocal passed
        actual = moonbit.get(name, "")
        if isinstance(cantools_value, float):
            agrees = actual != "" and float(actual) == cantools_value
        elif isinstance(cantools_value, str):
            agrees = actual.upper() == cantools_value.upper()
        else:
            agrees = actual == str(cantools_value)
        check(agrees, f"MoonBit/cantools agree: {name}")

    intel_payload = bytes.fromhex("A0 BC")
    intel_raw = intel.decode(intel_payload, decode_choices=False, scaling=False)["IntelValue"]
    intel_physical = intel.decode(intel_payload, decode_choices=False, scaling=True)["IntelValue"]
    check(intel_raw == 3018, "Intel cross-byte raw A0 BC -> 0xBCA")
    cross_check("intel_raw", intel_raw)
    check(intel_physical == 1508.0, "Intel factor/offset -> physical 1508.0")
    cross_check("intel_physical", intel_physical)
    check(intel.encode({"IntelValue": 3018}, scaling=False, strict=True) == intel_payload,
          "Intel raw encode round-trip")
    cross_check("intel_encoded", intel.encode({"IntelValue": 3018}, scaling=False).hex().upper())
    check(intel.encode({"IntelValue": 1508.0}, scaling=True, strict=True) == intel_payload,
          "Intel physical encode round-trip")

    motorola_payload = bytes.fromhex("AB C0")
    motorola_raw = motorola.decode(motorola_payload, decode_choices=False, scaling=False)["MotorolaValue"]
    check(motorola_raw == 0xABC, "Motorola sawtooth cross-byte AB C0 -> 0xABC")
    cross_check("motorola_raw", motorola_raw)
    check(motorola.encode({"MotorolaValue": 0xABC}, scaling=False, strict=True) == motorola_payload,
          "Motorola raw encode round-trip")
    cross_check("motorola_encoded", motorola.encode({"MotorolaValue": 0xABC}, scaling=False).hex().upper())

    low = bytes.fromhex("00 08")
    high = bytes.fromhex("FF 07")
    check(signed.decode(low, decode_choices=False, scaling=False)["SignedValue"] == -2048,
          "signed 12-bit minimum")
    cross_check("signed_min", signed.decode(low, decode_choices=False, scaling=False)["SignedValue"])
    check(signed.decode(high, decode_choices=False, scaling=False)["SignedValue"] == 2047,
          "signed 12-bit maximum")
    cross_check("signed_max", signed.decode(high, decode_choices=False, scaling=False)["SignedValue"])
    check(signed.encode({"SignedValue": -2048}, scaling=False, strict=True) == low,
          "signed minimum encode round-trip")
    check(signed.encode({"SignedValue": 2047}, scaling=False, strict=True) == high,
          "signed maximum encode round-trip")

    out_of_range_failed = False
    try:
        intel.encode({"IntelValue": 5000.0}, scaling=True, strict=True)
    except (cantools.database.errors.EncodeError, ValueError):
        out_of_range_failed = True
    check(out_of_range_failed, "out-of-range physical input rejected")

    dlc_failed = False
    try:
        intel.decode(bytes.fromhex("A0"), decode_choices=False, scaling=False)
    except cantools.database.errors.DecodeError:
        dlc_failed = True
    check(dlc_failed, "truncated DLC rejected")

    malformed_failed = False
    try:
        cantools.database.load_string(HEADER + "BO_ nope Broken: 2 ECU\n", database_format="dbc")
    except Exception:
        malformed_failed = True
    check(malformed_failed, "malformed DBC rejected")

    check(not standard_frame.is_extended_frame, "cantools classifies standard CAN frame")
    check(extended_frame.is_extended_frame, "cantools classifies DBC-marked extended CAN frame")
    standard_payload = bytes.fromhex("11")
    extended_payload = bytes.fromhex("22")
    standard_cli = subprocess.run(
        ["moon", "run", "cmd/moondbc", "--", "decode", "testdata/extended_can.dbc",
         "--frame-id", "291", "--data", standard_payload.hex()],
        check=True, capture_output=True, text=True,
    ).stdout
    extended_cli = subprocess.run(
        ["moon", "run", "cmd/moondbc", "--", "decode", "testdata/extended_can.dbc",
         "--frame-id", "291", "--data", extended_payload.hex(), "--extended"],
        check=True, capture_output=True, text=True,
    ).stdout
    standard_raw = standard_frame.decode(standard_payload, decode_choices=False, scaling=False)["Value"]
    extended_raw = extended_frame.decode(extended_payload, decode_choices=False, scaling=False)["Value"]
    check(f"raw={standard_raw}" in standard_cli, "MoonBit/cantools agree: standard frame ID dispatch")
    check(f"raw={extended_raw}" in extended_cli, "MoonBit/cantools agree: extended frame ID dispatch")

    mux_database = cantools.database.load_file("testdata/multiplexed.dbc")
    mux_message = mux_database.get_message_by_name("Mux")
    for selector, branch_name, payload in [(1, "A", bytes.fromhex("01 2A")),
                                            (2, "B", bytes.fromhex("02 63"))]:
        expected = mux_message.decode(payload, decode_choices=False, scaling=False)
        moonbit_decode = subprocess.run(
            ["moon", "run", "cmd/moondbc", "--", "decode", "testdata/multiplexed.dbc",
             "--frame-id", "700", "--data", payload.hex(), "--json"],
            check=True, capture_output=True, text=True,
        ).stdout
        actual = json.loads(moonbit_decode)
        actual_signals = {item["name"]: int(item["raw"]) for item in actual["signals"]}
        check(
            actual_signals == expected,
            f"MoonBit/cantools agree: multiplex selector {selector} active decode",
        )
        encoded = mux_message.encode(expected, scaling=False, strict=True)
        moonbit_encode = subprocess.run(
            ["moon", "run", "cmd/moondbc", "--", "encode", "testdata/multiplexed.dbc",
             "--message", "Mux", "--signal", f"Mode={selector}", "--signal", "Base=0",
             "--signal", f"{branch_name}={expected[branch_name]}"],
            check=True, capture_output=True, text=True,
        ).stdout
        check(encoded.hex().upper() in moonbit_encode,
              f"MoonBit/cantools agree: multiplex selector {selector} encode")

    for index, width in enumerate(MOTOROLA_WIDTHS):
        unsigned_id = 300 + index * 2
        signed_id = unsigned_id + 1
        unsigned_max = (1 << width) - 1
        signed_min = -(1 << (width - 1))
        signed_max = (1 << (width - 1)) - 1
        unsigned_message = database.get_message_by_frame_id(unsigned_id)
        signed_message = database.get_message_by_frame_id(signed_id)

        unsigned_hex = moonbit[f"motorola_u_{width}_hex"]
        unsigned_payload = bytes.fromhex(unsigned_hex)
        check(
            unsigned_message.decode(unsigned_payload, scaling=False)["Value"] == unsigned_max,
            f"cantools Motorola unsigned width {width} max decode",
        )
        check(
            unsigned_message.encode({"Value": unsigned_max}, scaling=False, strict=True)
            == unsigned_payload,
            f"cantools Motorola unsigned width {width} max encode",
        )
        check(
            int(moonbit[f"motorola_u_{width}_raw"]) == unsigned_max,
            f"MoonBit Motorola unsigned width {width} raw round-trip",
        )

        for label, value in [("smin", signed_min), ("smax", signed_max)]:
            payload = bytes.fromhex(moonbit[f"motorola_{label}_{width}_hex"])
            check(
                signed_message.decode(payload, scaling=False)["Value"] == value,
                f"cantools Motorola signed width {width} {label} decode",
            )
            check(
                signed_message.encode({"Value": value}, scaling=False, strict=True) == payload,
                f"cantools Motorola signed width {width} {label} encode",
            )
            check(
                int(moonbit[f"motorola_{label}_{width}_raw"]) == value,
                f"MoonBit Motorola signed width {width} {label} raw round-trip",
            )

    print(json.dumps({"cantools_version": cantools.__version__, "cantools_comparisons": passed, "checks": len(results), "result": "PASS"}))


if __name__ == "__main__":
    main()
