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
| `CM_` | Validated superficially, diagnostic and skipped | Comments are not retained in the schema. |
| `VAL_` | Validated superficially, diagnostic and skipped | Choice labels do not alter raw numeric values; labels are not retained. |
| `BA_DEF_`, `BA_DEF_DEF_` | Validated superficially, diagnostic and skipped | Definitions/defaults are not applied. |
| Known non-layout `BA_` assignments | Diagnostic and skipped | Only names explicitly allowlisted by the current parser are skipped. |
| Other `BA_` assignments | Rejected | Attributes can change frame/signal interpretation. |
| Integer `SIG_VALTYPE_` | Diagnostic and skipped | Explicit integer type leaves the supported integer interpretation unchanged. |
| Floating `SIG_VALTYPE_` | Rejected | Floating representation is not implemented. |
| Extended CAN identifier | Rejected | Identifier format is not silently treated as a standard 11-bit ID. |
| Multiplexing | Rejected | Multiplexor-dependent signal interpretation is unsupported. |
| CAN FD, ARXML | Not implemented | Outside the current parser and codec. |

The accepted message ID range is 0–2047 and DLC is 0–8. See the parser source
and tests for precise syntax checks; DBC dialects can vary, and this matrix does
not claim complete DBC standard compatibility.
