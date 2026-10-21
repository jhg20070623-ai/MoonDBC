# DBC support matrix

This table describes the implemented subset; recognizing a declaration does
not imply that MoonDBC preserves it in a round-trip writer.

| Declaration or feature | Status | Behavior |
| --- | --- | --- |
| `BO_`, `SG_` | Parsed | Message and integer signal definitions build the codec schema. |
| `VERSION` | Diagnostic and skipped | Version text is reported as metadata and does not alter codec state. |
| Multiline `NS_` | Recognized and skipped | Namespace token list is scanned until `BS_:`; unknown namespace entries are diagnosed. |
| `BS_:` | Diagnostic and skipped | Bus timing is not part of this signal codec. |
| `BU_:` | Diagnostic and skipped | Node names are not retained. |
| `CM_` | Network, node, message, and signal comments parsed and retained | References are validated; inspect output escapes quotes, backslashes, and control characters. |
| `VAL_` | Parsed and retained | Integer raw-value/label pairs are attached to their message and signal. Raw values are range-checked using the signal's signedness and bit width. `lookup_value_label` and `lookup_raw_value` expose the mapping; ambiguous duplicate mappings are reported by `validate_schema`. |
| `BA_DEF_`, `BA_DEF_DEF_` | Validated superficially, diagnostic and skipped | Definitions/defaults are not applied. |
| Known non-layout `BA_` assignments | Diagnostic and skipped | Only names explicitly allowlisted by the current parser are skipped. |
| Other `BA_` assignments | Rejected | Attributes can change frame/signal interpretation. |
| Integer `SIG_VALTYPE_` | Diagnostic and skipped | Explicit integer type leaves the supported integer interpretation unchanged. |
| Floating `SIG_VALTYPE_` | Rejected | Floating representation is not implemented. |
| Extended CAN identifier | Supported | DBC bit-31 marker is preserved in the schema; CLI frame matching uses the actual 29-bit ID and explicit standard/extended frame type. |
| Offline `candump -L` batch decode | Supported subset | CLI accepts `(timestamp) interface ID#DATA` classic CAN records with 3-digit standard or 8-digit extended IDs; emits ordered NDJSON and rejects CAN FD/other spellings with line-numbered errors. |
| Single-level integer multiplexing | Supported subset | One leading unsigned `M` selector of at most 31 bits and exact `mN` branches. Decode and encode include only the selected branch; overlapping branch layouts are accepted only for distinct selector values. |
| Nested, ranged, or multiple-selector multiplexing | Rejected | Unsupported selector syntax or branch semantics produce an explicit parser/schema error. |
| CAN FD, ARXML | Not implemented | Outside the current parser and codec. |

The accepted standard CAN ID range is 0–2047; extended CAN IDs range from 0 to
0x1FFFFFFF and are represented in DBC message identifiers using the bit-31
extended-frame marker. DLC is 0–8. See the parser source and tests for precise
syntax checks; DBC dialects can vary, and this matrix does not claim complete
DBC standard compatibility.
