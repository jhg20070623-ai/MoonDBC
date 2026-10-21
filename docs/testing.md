# Testing

Run from the repository root with the installed MoonBit toolchain:

```sh
moon fmt --check
moon check
moon test
moon run scripts/integration_test.mbtx
```

`scripts/integration_test.mbtx` launches the actual CLI with working directory
set to the repository root. DBC paths in the test commands are therefore
root-relative. A missing path produces a CLI failure that includes the
requested path; it is not replaced by embedded fixture text.

The MoonBit suite retains the Stage 2.1 tests and adds database-level named
frame API coverage. The integration script covers minimal, common-header, and
unsupported-semantics disk fixtures; inspect; Intel decode/encode; physical
encode success and rejection; argument errors; and missing files.

For the optional independent oracle:

```sh
python -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements-dev.txt  # Windows
.venv/Scripts/python.exe scripts/cantools_compare.py                # Windows
```

On Unix, activate `.venv`, install the same requirements, then run
`python scripts/cantools_compare.py`. The script builds comparison schemas
in-memory from test data authored in this repository. cantools is not imported
by the library or CLI.
