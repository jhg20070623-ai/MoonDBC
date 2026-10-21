# Limitations

- The parser implements a defined classic CAN DBC subset, not the complete DBC
  grammar. Some metadata is skipped with diagnostics rather than preserved.
- Only single-level integer multiplexing with one leading selector and exact
  `mN` branches is supported. Nested, ranged, or multiple-selector forms,
  floating-point signal types, and potentially layout-changing attributes are
  rejected. Standard and extended classic CAN
  identifiers are supported; extended identifiers use DBC's bit-31 marker in
  the schema and explicit frame-type selection in the frame-level CLI/API.
- The codec is signal-level software. It does not open CAN hardware, listen to
  a bus, parse capture formats, or implement transport protocols.
- Physical conversions use `Double` and are limited by the explicit 2^53 raw
  integer precision policy. Raw integer APIs remain exact over their supported
  64-bit types.
- CLI encoding accepts raw integer values by default. The `--physical` option
  applies the library's physical-to-raw conversion rules and rejects values
  that are out of range or do not map exactly to an integer raw value.
- No vendor DBC files are included. Tests use hand-written synthetic data.
- Local tests do not establish acceptance of the project topic by the event
  organizers. Their response to the earlier project inquiry was still pending
  in the source Stage 3 brief.
