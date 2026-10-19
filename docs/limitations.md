# Limitations

- The parser implements a defined classic CAN DBC subset, not the complete DBC
  grammar. Some metadata is skipped with diagnostics rather than preserved.
- Extended CAN identifiers, multiplexed signals, floating-point signal types,
  and potentially layout-changing attributes are rejected.
- The codec is signal-level software. It does not open CAN hardware, listen to
  a bus, parse capture formats, or implement transport protocols.
- Physical conversions use `Double` and are limited by the explicit 2^53 raw
  integer precision policy. Raw integer APIs remain exact over their supported
  64-bit types.
- The CLI encode command accepts raw integer values. Physical encoding is
  currently available through the library API.
- No vendor DBC files are included. Tests use hand-written synthetic data.
- Local tests do not establish acceptance of the project topic by the event
  organizers. Their response to the earlier project inquiry was still pending
  in the source Stage 3 brief.
