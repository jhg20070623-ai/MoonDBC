# Stage 5B GitHub publication report

Audit date: 2026-10-19

## Publication result

- Public repository: [jhg20070623-ai/MoonDBC](https://github.com/jhg20070623-ai/MoonDBC)
- Default branch: `main`
- Published release: [v0.1.0](https://github.com/jhg20070623-ai/MoonDBC/releases/tag/v0.1.0)
- Annotated tag `v0.1.0` points to commit `da5324b45d14c32fff2c8c57f5bc9ad90034ba4d`.
- That commit's GitHub Actions run [39252776894](https://github.com/jhg20070623-ai/MoonDBC/actions/runs/39252776894) completed successfully. Both the MoonBit/CLI/fixture job and the independent cantools comparison job passed.
- The published `main` history contains eight non-empty commits at release time. The five original local commits were retained as real history, with their author and committer email rewritten to the user-confirmed GitHub noreply address. No MoonSim commits were reused.

## Validation evidence

The successful GitHub Actions run for the tagged commit performed:

- MoonBit dependency resolution and toolchain setup.
- `moon fmt --check`, `moon check`, and `moon test`.
- Native CLI build.
- File-based CLI integration tests and validation of the primary DBC fixtures.
- The project examples.
- Python 3.14 setup and cantools 45.0.0 comparison: 101 checks, including 61 direct comparisons, with result `PASS` and no mismatches.

The same source had also passed local verification before publication: 33 MoonBit tests, 8 file-level CLI checks, and the same 101/61 cantools comparison. Earlier remote CI attempts exposed a wrong MoonBit compiler version identifier and missing clean-runner dependency resolution. Both were corrected and are covered by the passing run above.

## Release content and scope

Release notes are in [`releases/v0.1.0.md`](releases/v0.1.0.md). The release documents MoonDBC as a MoonBit library and CLI for a supported subset of classic CAN DBC integer signals. It does not claim complete DBC compatibility. Extended identifiers, multiplexing, floating-point signals, ARXML, and hardware interfaces remain unsupported.

The repository is public and declares Apache-2.0 in its license file and project metadata. The published fixtures are project-authored synthetic data. cantools is used only as a development-time comparison tool. No vendor DBC data or private vehicle data is included.

## Clone verification and remaining caveat

A fresh public `git clone` was attempted after release, but this machine's HTTPS connection to `github.com:443` was reset/timed out during the transfer. No local clean-clone result is claimed. The hosted GitHub Actions run did check out the exact tagged commit into clean Ubuntu runners and completed all configured build, test, fixture, example, and comparison steps successfully.

The GitHub Release is published. No Mooncakes package was published and no contest application was submitted.
