# Architecture

MoonDBC separates schema processing from operating-system I/O:

1. `parse_dbc(source)` parses a supported DBC text subset into
   `DbcDatabase` and emits non-fatal metadata diagnostics.
2. `validate_schema(database)` checks message and signal invariants.
3. `decode_frame` / `encode_frame` resolve message identity and signal names,
   validate the schema, and call the raw codec.
4. `cmd/moondbc` reads files through the MoonBit async filesystem package,
   parses arguments, formats diagnostics, and delegates all codec work to the
   library.

Raw integer values are a tagged union of `UInt64` and `Int64`. Intel and
Motorola bit traversal are handled by the core codec. Physical value conversion
is a separate operation and follows the precision policy in
[`codec-precision-policy.md`](codec-precision-policy.md).

The core library imports MoonBit standard packages only. Python and cantools
appear only in the development comparison tooling. The executable package uses
the MoonBit async filesystem dependency for file reads.
