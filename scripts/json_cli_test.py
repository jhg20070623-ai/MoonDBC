import json
import subprocess
import sys


def run_cli(*args, expect_success=True):
    result = subprocess.run(
        ["moon", "run", "cmd/moondbc", "--", *args],
        text=True,
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

print(f"PASS: {checks} JSON CLI checks; output parsed with Python json")
