# Stage 5A publication gate

Audit date: 2026-10-19
Scope: local MoonDBC repository and a fresh temporary clone. No remote was
configured, created, or pushed; no Mooncakes publication or GitHub release was
made.

## Decision

**Stage 5A technical preparation: PASS with conditions. Public release: BLOCKED.**

The project sources and command examples passed again, including in a fresh
clone with an isolated MoonBit user profile and a newly downloaded dependency.
Before a public push, the project owner must confirm the copyright holder and
Apache-2.0 grant, decide whether the current Git author email may be public (or
replace it throughout the local history), and confirm the target GitHub
repository is available. Remote CI is also unrun.

## Local Git baseline

The audited branch is `main`, with no configured remote. The first four
commits in the local history are:

| Commit | Subject |
| --- | --- |
| `cd99cf0d427842af8422429c9f4ebc504d5c94f1` | `chore: establish MoonDBC local repository baseline` |
| `cbe2670f4f8761c229e9cd1200ad209cebc51fb5` | `docs: record MoonDBC Stage 4 release audit` |
| `e2ff06b` | `ci: pin MoonBit and Python toolchains` |
| `d38b3a6eeb4f0f6ca326b74db4188b6bf56fe5a4` | `ci: pin GitHub Actions and runner versions` |

The workflow, Python dependency, and Stage 5A audit report changes are
committed locally. This report is an additional audit commit after the four
listed above. No MoonSim or MoonDBC-POC repository was touched.

## Reproducibility configuration

The workflow now selects:

| Component | Pinned value |
| --- | --- |
| Runner image | `ubuntu-24.04` |
| `actions/checkout` | `v7.0.1` |
| MoonBit setup action | `hustcer/setup-moonbit@v1.25` |
| MoonBit toolchain package (`version`) | `0.1.20260920` |
| MoonBit core package (`core-version`) | `0.10.14+7d59c7ec9` |
| `actions/setup-python` | `v7.0.0` |
| Python | `3.14.3` |
| cantools | `45.0.0` |

The setup action exposes separate `version` and `core-version` inputs; the
first is the MoonBit toolchain package, not the `moonc` compiler version. The
local installation reports `moon 0.1.20260920`, `moonc
v0.10.14+7d59c7ec9`, and `moonrun 0.1.20260920`. The local core manifest also
identifies `moonbitlang/core` as `0.10.14+7d59c7ec9`.

`requirements-dev.txt` pins cantools and the eight other packages in the
verified Python development dependency closure. `moon.mod` pins the sole
MoonBit dependency to `moonbitlang/async@0.20.2`. There is no MoonBit lock file;
the clean-clone run resolved this exact module version from a freshly updated
registry. Therefore the MoonBit version is pinned, but a content hash lock is
not present.

The action references are explicit release tags, not immutable commit SHAs.
The `setup-moonbit` v1.25 action metadata documents both version inputs and
its v1.25 changelog is dated 2026-09-04:
[action metadata](https://github.com/hustcer/setup-moonbit/blob/v1.25/action.yaml),
[v1.25 changelog](https://github.com/hustcer/setup-moonbit/blob/v1.25/CHANGELOG.md).
The GitHub action release pages list the pinned checkout and Python versions:
[checkout releases](https://github.com/actions/checkout/releases),
[setup-python releases](https://github.com/actions/setup-python/releases).

The dependency `moonbitlang/async@0.20.2` still emits a deprecation warning
because its own manifest uses `exclude`. It was not changed or blindly
upgraded. No MoonBit source warning or check error was emitted.

## Verification evidence

The commands below were run in the working tree and again from a fresh clone
of commit `d38b3a6eeb4f0f6ca326b74db4188b6bf56fe5a4`:

| Check | Result |
| --- | --- |
| `moon version --all` | `moon 0.1.20260920`; `moonc v0.10.14+7d59c7ec9`; `moonrun 0.1.20260920` |
| `moon update` in fresh profile | PASS; registry updated and `async@0.20.2` downloaded into the isolated profile |
| `moon fmt --check` | PASS, exit 0 |
| `moon check` | PASS, exit 0; no project errors or warnings |
| `moon test` | PASS, 33 passed / 0 failed |
| `moon build cmd/moondbc --target native` | PASS, exit 0 |
| `moon run scripts/integration_test.mbtx` | PASS, 8 checks; unsupported semantic fixture is rejected as expected |
| `moon run examples/api_demo` | PASS; prints `Speed=3018`, `Mode=0` |
| `validate testdata/minimal.dbc` | PASS |
| `validate testdata/common_header.dbc` | PASS |
| `inspect testdata/common_header.dbc` | PASS; reports its message and two signals |
| `decode ... --data A0BC` | PASS; `IntelValue` raw `3018`, physical `1508` |
| `encode ... IntelValue=3018 --signal Mode=2` | PASS; outputs `A2BC` |
| `scripts/cantools_compare.py` | PASS; cantools 45.0.0, 101 checks, 61 comparisons, 0 mismatches |

The clone was created from local Git with `--no-hardlinks`; it did not copy the
project's `.venv`, `_build`, `.mooncakes`, or user MoonBit cache. Its
`USERPROFILE` and MoonBit package cache were fresh. The exact installed MoonBit
toolchain payload was copied into an isolated `MOONBIT_HOME`, and the exact
`async@0.20.2` dependency was fetched into the fresh profile. Python packages
were installed in a new virtual environment with pip cache disabled.

The toolchain package was not downloaded from its upstream artifact URL in
this audit: direct access to `cli.moonbitlang.com` returned HTTP 403 in this
environment. Thus the clean-clone check proves a cold project/dependency
rebuild with the exact installed compiler payload, but does not independently
prove the `setup-moonbit` action can fetch that payload on a GitHub runner.

## Source, rights, and privacy

| Check | Status | Evidence / remaining action |
| --- | --- | --- |
| Apache-2.0 text and declarations | PASS | Root `LICENSE`, `moon.mod`, and README declare Apache-2.0. |
| Copyright holder and authority to license | BLOCKED | No copyright owner was verified. The LICENSE retains the standard example placeholder; no name or year was inserted. Owner confirmation and a correct notice are required before public distribution. |
| `NOTICE` file | PASS | No project-specific NOTICE obligation was identified: no third-party source or vendor DBC is bundled and no upstream NOTICE text was copied. Reassess if contents change. |
| Third-party code and dependency origin | PASS | MoonBit `async` and Python cantools packages are dependencies, not copied project source. cantools is only a development comparison tool. Earlier dependency/license inventory is in `docs/stage4-release-audit.md`. |
| DBC fixture rights | PASS | Three project-authored synthetic fixtures; no vendor DBC is included. |
| Tracked source privacy scan | PASS | No supplied phone/email, token pattern, private key, or machine absolute path was found in tracked source and project docs. No project cache or build output is tracked. |
| Git commit identity privacy | BLOCKED | Existing commits contain a contact email as author and committer metadata. A public push would expose it. The owner must accept that exposure or choose a public-safe identity and authorize rewriting the local history before Stage 5B. |

`LICENSE` is a standard Apache-2.0 license text. It does not by itself verify
that the project author has authority to grant the stated license. The project
metadata and README currently make that declaration provisionally; do not
interpret this technical audit as legal confirmation.

## GitHub target and CI

The requested target is `jhg20070623-ai/MoonDBC`. An unauthenticated direct
repository page returned 404, and the `gh repo view` query could not resolve
that repository. This is evidence that no repository was
accessible to these checks, not proof that the name is available: a private
repository or account/permission condition can also be undiscoverable. Confirm
availability immediately before Stage 5B.

The workflow was statically reviewed. It grants only `contents: read` and
contains separate MoonBit and optional cantools jobs with formatting, type
check, tests, native build, fixture integration, CLI examples, and comparison.
No secret is configured. No remote is configured in the local repository, so
remote CI status is **BLOCKED / NOT RUN**; no successful Actions run is
claimed.

## Planned GitHub file set

The candidate public tree consists of the following 35 tracked project files
after this report is committed. Git metadata is not included in the file set.

```text
.github/workflows/ci.yml
.gitignore
CHANGELOG.md
LICENSE
README.md
moon.mod
moon.pkg
moondbc.mbt
moondbc_test.mbt
moondbc_wbtest.mbt
pkg.generated.mbti
requirements-dev.txt
cmd/moondbc/main.mbt
cmd/moondbc/moon.pkg
cmd/moondbc/pkg.generated.mbti
cmd/vectors/main.mbt
cmd/vectors/moon.pkg
cmd/vectors/pkg.generated.mbti
docs/architecture.md
docs/codec-precision-policy.md
docs/limitations.md
docs/stage3-readiness.md
docs/stage4-release-audit.md
docs/stage5-publication-gate.md
docs/support-matrix.md
docs/testing.md
examples/README.md
examples/api_demo/main.mbt
examples/api_demo/moon.pkg
examples/api_demo/pkg.generated.mbti
scripts/cantools_compare.py
scripts/integration_test.mbtx
testdata/common_header.dbc
testdata/minimal.dbc
testdata/unsupported_semantics.dbc
```

This is a proposed file inventory only. It does not authorize public release.

## Release gate summary

| Gate | Status |
| --- | --- |
| Local Git history and clean-clone source build | PASS |
| Core tests, CLI, fixtures, cantools comparison | PASS |
| Reproducible version selection in workflow | PASS with action-tag and no-MoonBit-lockfile caveats |
| Remote workflow execution | BLOCKED / NOT RUN |
| Copyright ownership and Apache-2.0 authorization | BLOCKED |
| Public exposure of current commit email | BLOCKED pending owner choice |
| Target repository availability | BLOCKED / not conclusively known |
| Public release authorization | BLOCKED pending explicit confirmation |

No remote, push, GitHub release, Mooncakes publication, or contest submission
was performed in Stage 5A.
