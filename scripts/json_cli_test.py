import json
import subprocess
import sys


def run_cli(*args, expect_success=True):
    result = subprocess.run(
        ["moon", "run", "cmd/moondbc", "--", *args],
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )
    if expect_success and result.returncode != 0:
        raise AssertionError(f"CLI failed: {result.stderr or result.stdout}")
    if not expect_success:
        if result.returncode == 0:
            raise AssertionError("invalid CLI input unexpectedly succeeded")
        return result
    return json.loads(result.stdout)


checks = 0
inspection = run_cli("inspect", "testdata/common_header.dbc", "--json")
checks += 1
assert inspection["messages"][0]["name"] == "CommonHeader"
checks += 1
network = next(c for c in inspection["comments"] if c["target"] == "network")
assert 'escaped quote: "ready"' in network["text"]
checks += 1
mode = next(s for s in inspection["messages"][0]["signals"] if s["name"] == "Mode")
assert mode["multiplexing"] == {"role": "none"}
assert mode["values"] == [
    {"raw": "0", "label": "Off"},
    {"raw": "1", "label": "On"},
    {"raw": "2", "label": "Hold"},
    {"raw": "3", "label": "Fault"},
]
checks += 1

multiplexed = run_cli("inspect", "testdata/multiplexed.dbc", "--json")
signals = multiplexed["messages"][0]["signals"]
assert next(s for s in signals if s["name"] == "Mode")["multiplexing"] == {
    "role": "selector"
}
assert next(s for s in signals if s["name"] == "A")["multiplexing"] == {
    "role": "branch",
    "value": 1,
}
checks += 1

decoded = run_cli("decode", "testdata/minimal.dbc", "--frame-id", "256", "--data", "A0BC", "--json")
signal = next(s for s in decoded["signals"] if s["name"] == "IntelValue")
assert signal["raw"] == "3018" and signal["physical"] == 1508.0
checks += 1

unsigned = run_cli("decode", "testdata/json_precision.dbc", "--frame-id", "512", "--data", "FFFFFFFFFFFFFFFF", "--json")
signal = unsigned["signals"][0]
assert signal["raw"] == "18446744073709551615"
assert signal["physical"] is None and signal["physical_status"] == "precision_exceeded"
checks += 1

signed = run_cli("decode", "testdata/json_precision.dbc", "--frame-id", "513", "--data", "0000000000000080", "--json")
signal = signed["signals"][0]
assert signal["raw"] == "-9223372036854775808"
checks += 1

invalid = run_cli("decode", "testdata/minimal.dbc", "--frame-id", "256", "--data", "A0", "--json", expect_success=False)
assert invalid.returncode != 0
checks += 1

valid_schema = run_cli("validate", "testdata/common_header.dbc", "--json")
assert valid_schema["valid"] is True
assert valid_schema["messages"] == 1 and valid_schema["signals"] == 2
assert isinstance(valid_schema["diagnostics"], list)
checks += 1

invalid_schema = run_cli(
    "validate", "testdata/invalid_schema.dbc", "--json"
)
schema_result = invalid_schema
assert schema_result["valid"] is False
diagnostics = schema_result["diagnostics"]
assert {diagnostic["code"] for diagnostic in diagnostics} >= {
    "DUPLICATE_MESSAGE_ID",
    "DUPLICATE_SIGNAL_NAME",
    "SIGNAL_OVERLAP",
}
assert all(
    diagnostic["severity"] in {"error", "warning"} for diagnostic in diagnostics
)
assert any(diagnostic["severity"] == "error" for diagnostic in diagnostics)
assert any(diagnostic["severity"] == "warning" for diagnostic in diagnostics)
lines_by_code = {diagnostic["code"]: diagnostic["line"] for diagnostic in diagnostics}
assert lines_by_code["DUPLICATE_SIGNAL_NAME"] == 5
assert lines_by_code["SIGNAL_OVERLAP"] == 5
assert lines_by_code["DUPLICATE_MESSAGE_ID"] == 7
checks += 1

print(f"PASS: {checks} JSON CLI checks; output parsed with Python json")
