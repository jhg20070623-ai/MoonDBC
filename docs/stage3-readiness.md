# Stage 3 readiness report

Date: 2026-10-18

## Result

The local MVP implementation and validation gates below passed. This is a
technical result only; it does not establish contest topic approval, full DBC
compatibility, or a successful remote CI run.

## Implemented

- An independent MoonBit module and core library containing the preserved
  Stage 2.1 parser, validator, raw codec, and physical conversion behavior.
- Database-level `decode_frame` and `encode_frame` APIs using message and
  signal names with structured errors.
- A CLI that reads DBC files and implements `validate`, `inspect`, `decode`,
  and raw integer `encode` commands through the core library.
- Three project-authored synthetic DBC fixtures on disk, a runnable library
  API example, file-level integration checks, documentation, and a GitHub
  Actions workflow.

## Validation evidence

| Check | Result |
| --- | --- |
| MoonBit toolchain | moon `0.1.20260920`; moonc `v0.10.14+7d59c7ec9`; moonrun `0.1.20260920` |
| `moon fmt --check` | Passed |
| `moon check` | Passed; 0 errors and 0 warnings |
| `moon test` | 33 passed, 0 failed; original 30 tests remain and 3 frame API tests were added |
| Native CLI build | `moon build cmd/moondbc --target native` passed |
| File-level CLI integration | 8 checks passed, invoking the CLI against all three on-disk fixtures |
| Runnable API example | `moon run examples/api_demo` passed; printed `Speed=3018` and `Mode=0` |
| cantools comparison | cantools 45.0.0; 101 checks and 61 MoonBit/reference comparisons passed; no mismatch |
| Remote GitHub Actions | Workflow added, but no remote run has been triggered or observed |

Running the standalone `.mbtx` integration script prints one deprecation
warning from the pinned third-party `moonbitlang/async@0.20.2` module's legacy
`exclude` setting. Project `moon check` reports no source warnings. The
generated root interface is recorded in `pkg.generated.mbti`.

The CLI integration script runs with the project root as its working directory.
Fixture paths are relative to that root. A missing file returns a failure with
the requested path in the diagnostic. `unsupported_semantics.dbc` fails with
`UnsupportedSemantic`; it is not interpreted as an ordinary standard frame.

The `minimal.dbc` CLI example decodes payload `A0BC` to raw `IntelValue=3018`
and `Mode=0`; physical value `1508` is available because the DBC explicitly
sets factor `0.5` and offset `-1`. Encoding raw `IntelValue=3018` with
`Mode=2` returns payload `A2BC`.

## Scope and known limitations

The project implements a classic CAN DBC subset, including `BO_` and `SG_`,
Intel and Motorola DBC bit layouts, signed/unsigned integers, scaling, and
schema validation. Some metadata is skipped with diagnostics. Extended frame
identifiers, multiplexing, floating signal types, CAN FD, ARXML, hardware I/O,
and complete DBC grammar compatibility are not implemented. Raw 64-bit integer
values remain exact; physical conversion uses `Double` and applies the 2^53
precision boundary documented in `codec-precision-policy.md`.

The code and authored fixtures are declared Apache-2.0 under this project's
`LICENSE` and module metadata. Fixtures are synthetic and contain no vendor
DBC. The project makes no license claim over the DBC specification or third-
party datasets. cantools is only a pinned development dependency.

## Git state

`MoonDBC/` is not initialized as a Git repository: it has no `.git` directory,
commit history, or remote. Therefore it has no Git clean/dirty status to report.
No MoonSim files or commits were copied or modified as part of this directory's
work.

## Recommendation

GO to a separately reviewed release-preparation stage: the local core, CLI,
fixtures, tests, and reference comparison meet the stated Stage 3 technical
checks. Before any release, initialize the project's own Git history, run the
configured workflow remotely, and consider the pending event-organizer topic
review separately. No repository, package, tag, release, or contest submission
was created in this stage.
