# Stage 4 release readiness audit

Date: 2026-10-19  
Scope: local MoonDBC directory only. No remote, package, release, or contest
submission was created.

## Status key

- **PASS** — direct evidence was collected in this audit.
- **FAIL** — an observed defect blocks the stated item.
- **BLOCKED** — requires an external event or a choice that was deliberately
  outside this stage.
- **NOT RUN** — no attempt was made in this stage.
- **WARN** — the check passed with a documented limitation or follow-up.

## Release candidate checklist

| Check | Status | Evidence |
| --- | --- | --- |
| Source and directory integrity | PASS | 33 non-generated files inventoried; no zero-byte files. Three authored fixtures, source, tests, CLI, example, scripts, and project docs are present. Largest source file is 33,302 bytes; no unexpectedly large file was found. |
| README and documentation references | PASS | Internal links refer to files in this directory; the README's optional Python command was clarified to use the virtual-environment interpreter. |
| Temporary files, caches, and generated output | PASS | `.venv/`, `.mooncakes/`, `_build/`, `__pycache__/`, and `*.pyc` are ignored. Generated build output was not added to Git. |
| Personal data, credentials, and local path scan | PASS | Source/document scan found no supplied phone/email, local absolute path, token pattern, private-key marker, TODO, or FIXME. The local Git author metadata uses the contact identity provided by the owner; it is not part of the project source files. |
| Third-party data and project boundary | PASS | The three DBC fixtures are hand-written synthetic data. cantools is used only by development comparison code. No vendor DBC or MoonSim files are present in the inventoried project files. |
| Local Git repository and traceable baseline | PASS | Branch `main`; initial source baseline commit `cd99cf0d427842af8422429c9f4ebc504d5c94f1`. No remote is configured. A second local commit records this audit and the documentation correction. |
| Staging hygiene | PASS | Initial commit contains 33 source/config/documentation files (3,620 insertions); no `.venv`, `.mooncakes`, or `_build` files were staged. |
| Git working tree | PASS | Clean after the audit-record commit; `git status --short --branch` was checked. |
| Project license file and declaration | WARN | Root `LICENSE` is the Apache License 2.0 text; `moon.mod` declares `Apache-2.0`; README says source and authored fixtures are under Apache-2.0. The standard license appendix still contains its generic example placeholder; this is not a project copyright notice. No contrary source license was found, but the owner should confirm the copyright attribution before public distribution. |
| MoonBit direct dependency license | PASS | `moon tree` lists `moonbitlang/async@0.20.2`; its installed `moon.mod` declares Apache-2.0. No further MoonBit dependency was listed. |
| Python development dependency licenses | WARN | Installed metadata was read for cantools 45.0.0 (MIT) and its transitive packages. See the dependency table below. The comparison environment is development-only and is not imported by MoonBit runtime code. |
| `async@0.20.2` deprecation | WARN | The package's manifest uses legacy `exclude`; the integration run emitted the package-manager deprecation warning. Project `moon check` emitted no source warnings. This third-party package was not edited. |
| `moon fmt --check` | PASS | Exit code 0; “no work to do”. |
| `moon check` | PASS | Exit code 0; no errors or warnings. |
| `moon test` | PASS | Exit code 0; 33 passed, 0 failed. |
| Native CLI build | PASS | `moon build cmd/moondbc --target native` exited 0. |
| Disk-fixture integration | PASS | `moon run scripts/integration_test.mbtx` exited 0; all 8 checks passed. Minimal and common-header fixtures validated; unsupported semantics were explicitly rejected. The run showed the noted third-party deprecation warning. |
| CLI decode / encode example | PASS | `A0BC` decoded to raw `IntelValue=3018`, physical `1508`, `Mode=0`; encoding `IntelValue=3018` and `Mode=2` returned `A2BC`. |
| Other README CLI examples | PASS | Both supported fixtures validated; common-header inspect showed the two parsed signals and emitted documented metadata warnings. |
| Runnable library example | PASS | `moon run examples/api_demo` exited 0 and printed `Speed=3018`, `Mode=0`. |
| cantools comparison | PASS | Python 3.14.3, cantools 45.0.0; `scripts/cantools_compare.py` exited 0 with 101 checks, 61 comparisons, and zero mismatches. |
| CI workflow static review | WARN | `.github/workflows/ci.yml` has read-only `contents` permission, separate MoonBit and optional cantools jobs, format/check/test/native-build/integration/fixture/example steps. Setup action and toolchain use mutable/default latest versions; Python is `3.x`. This is a reproducibility risk. |
| Remote CI result | BLOCKED | No remote is configured and no push was made, as required. The workflow has not run remotely in this stage. |
| Mooncakes publish / GitHub release | NOT RUN | Explicitly outside this stage. |
| Event-organizer approval | BLOCKED | Local engineering checks do not establish topic approval. No organizer response was verified in this audit. |
| Unconditional public-release readiness | BLOCKED | Remote CI evidence and owner confirmation of copyright attribution remain outstanding; no release was made. |

## Dependency inventory

`moon tree` and the installed package metadata were inspected locally. Python
versions below are the versions in the comparison environment on this machine;
the workflow currently requests the latest Python `3.x`, so remote resolution
may differ.

| Scope | Package | Version | License metadata | Notes |
| --- | --- | --- | --- | --- |
| MoonBit direct/runtime | `moonbitlang/async` | 0.20.2 | Apache-2.0 | Used by the CLI filesystem layer; legacy `exclude` field warning. |
| Python direct/dev | `cantools` | 45.0.0 | MIT | Pinned in `requirements-dev.txt`; comparison oracle only. |
| Python transitive/dev | `argparse-addons` | 0.12.0 | MIT | Installed metadata `License` field. |
| Python transitive/dev | `bitstruct` | 8.23.0 | MIT | Installed metadata `License-Expression` field. |
| Python transitive/dev | `crccheck` | 1.3.1 | MIT | Installed metadata `License` field. |
| Python transitive/dev | `packaging` | 26.3 | Apache-2.0 OR BSD-2-Clause | Installed metadata `License-Expression` field. |
| Python transitive/dev | `python-can` | 4.6.1 | LGPL-3.0-only | Required by cantools in the development environment; not a MoonBit runtime dependency. |
| Python transitive/dev | `textparser` | 0.26.2 | MIT | Installed metadata `License` field. |
| Python transitive/dev | `typing_extensions` | 4.16.0 | PSF-2.0 | Installed metadata `License-Expression` field. |
| Python transitive/dev | `wrapt` | 1.17.3 | BSD | Installed metadata `License` field. |

Python transitive versions are not pinned in `requirements-dev.txt`; this means
fresh comparison environments can resolve different compatible versions.
No vendored dependency source was found in the inventoried project files.

## Source and data provenance

- MoonBit implementation and project documentation are maintained in this
  independent `MoonDBC` directory. The Stage 3 report describes its parser as
  continued from the earlier MoonDBC POC; that provenance is not a MoonSim
  history or a claim of third-party originality.
- `testdata/minimal.dbc`, `common_header.dbc`, and
  `unsupported_semantics.dbc` are project-authored synthetic fixtures.
- The cantools comparison builds reference schemas in memory from project
  vectors; no vendor DBC is read or redistributed.
- The DBC syntax/specification and cantools remain third-party works. This
  project does not claim ownership of either.

## Workflow review details

The workflow runs on pushes and pull requests with `contents: read`. It checks
formatting, types, tests, native CLI build, file-level CLI integration, two
supported disk fixtures, and examples. A separate job installs the optional
Python oracle and runs the vector comparison. That job requires network access
to install Python packages; the MoonBit job also relies on the setup action to
install/download the toolchain. No secrets or broader repository permissions
are configured.

The setup action is `hustcer/setup-moonbit@v1`, which in this file leaves the
toolchain at the action's default. The [action documentation](https://github.com/hustcer/setup-moonbit#inputs)
describes that default as `latest`; pinning an explicit compatible version
would make CI more reproducible. This audit did not change the workflow and
cannot claim that a remote runner passed.

## Recommendation

**Conditional release preparation only.** The local MoonBit core, CLI, fixtures,
example, and cantools comparison passed this audit. Before public distribution,
confirm the copyright holder/notice, pin the CI toolchain and Python dependency
closure if reproducibility is required, and obtain an actual remote CI result.
This audit makes no claim of complete DBC compatibility or event approval.
