import json
import subprocess


result = subprocess.run(
    [
        "moon",
        "run",
        "cmd/moondbc",
        "--",
        "decode-log",
        "testdata/candump.dbc",
        "testdata/candump.log",
    ],
    text=True,
    capture_output=True,
    check=False,
)
if result.returncode != 0:
    raise AssertionError(f"decode-log failed: {result.stderr or result.stdout}")

records = [json.loads(line) for line in result.stdout.splitlines()]
assert len(records) == 3
assert [record["line"] for record in records] == [1, 2, 3]
assert [record["timestamp"] for record in records] == [
    "1.000001",
    "1.000002",
    "1.000003",
]
assert [record["decoded"]["message"] for record in records] == [
    "Minimal",
    "Minimal",
    "ExtendedFrame",
]
assert records[0]["decoded"]["signals"][0]["raw"] == "3018"
assert records[0]["decoded"]["signals"][0]["physical"] == 1508.0
assert records[2]["decoded"]["extended"] is True
assert records[2]["decoded"]["frame_id"] == 291

bad = subprocess.run(
    [
        "moon",
        "run",
        "cmd/moondbc",
        "--",
        "decode-log",
        "testdata/candump.dbc",
        "testdata/candump_bad.log",
    ],
    text=True,
    capture_output=True,
    check=False,
)
assert bad.returncode != 0
assert "candump line 2" in bad.stderr or "candump line 2" in bad.stdout, (
    f"expected a line-numbered diagnostic, got stdout={bad.stdout!r}, "
    f"stderr={bad.stderr!r}"
)
json_lines = []
for line in bad.stdout.splitlines():
    try:
        json.loads(line)
        json_lines.append(line)
    except json.JSONDecodeError:
        pass
assert len(json_lines) == 1, (
    f"expected one completed NDJSON record before failure, got {json_lines!r}"
)
print("PASS: 12 candump NDJSON and error-diagnostic checks")
