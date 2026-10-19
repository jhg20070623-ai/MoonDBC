///|
/// Byte order used by the DBC signal bit layout.
pub(all) enum ByteOrder {
  Intel
  Motorola
}

///|
/// DBC integer signal signedness.
pub(all) enum Signedness {
  Unsigned
  Signed
}

///|
/// A raw integer value without losing unsigned 64-bit payloads.
pub(all) enum RawSignalValue {
  UnsignedValue(UInt64)
  SignedValue(Int64)
}

///|
/// A DBC signal declaration. `start_bit` follows DBC numbering:
/// Intel counts upward from the least-significant bit; Motorola uses sawtooth
/// numbering and starts at the signal's most-significant bit.
pub(all) struct SignalDefinition {
  name : String
  start_bit : Int
  bit_length : Int
  byte_order : ByteOrder
  signedness : Signedness
  factor : Double
  offset : Double
  minimum : Double?
  maximum : Double?
  unit : String
  source_line : Int
}

///|
/// A classic CAN DBC message definition.
pub(all) struct MessageDefinition {
  id : UInt
  name : String
  dlc : Int
  signals : Array[SignalDefinition]
  source_line : Int
}

///|
/// Parsed, minimal DBC database.
pub(all) struct DbcDatabase {
  messages : Array[MessageDefinition]
  diagnostics : Array[ParseDiagnostic]
}

///|
/// Non-fatal metadata skipped because it does not alter this codec's signal
/// layout. Callers can surface these diagnostics to users.
pub(all) struct ParseDiagnostic {
  line : Int
  code : String
  message : String
}

///|
pub(all) enum ParseErrorKind {
  InvalidField
  UnsupportedSyntax
  UnsupportedSemantic
  SignalWithoutMessage
  InvalidMessage
  InvalidSignal
}

///|
/// Structured parser failure with one-based source line.
pub(all) struct ParseError {
  line : Int
  kind : ParseErrorKind
  message : String
}

///|
pub(all) enum IssueSeverity {
  Error
  Warning
}

///|
pub(all) struct ValidationIssue {
  severity : IssueSeverity
  code : String
  message : String
  line : Int
}

///|
pub(all) enum CodecError {
  InvalidBitLength
  InvalidSignalRange
  FrameTooShort
  DlcMismatch
  RawSignednessMismatch
  RawOutOfRange
  InvalidScale
  InvalidPhysicalValue
  PhysicalValueNotRepresentable
  PhysicalPrecisionExceeded
  PhysicalOutOfRange
}

///|
/// Errors returned by database-level frame operations.
pub(all) enum FrameError {
  UnknownMessageId(UInt)
  UnknownMessageName(String)
  InvalidSchema(String)
  MissingSignalValue(String)
  DuplicateSignalValue(String)
  UnknownSignalValue(String)
  Codec(CodecError)
}

///|
/// A decoded frame with the message identity and raw signal values.
pub(all) struct DecodedFrame {
  message_id : UInt
  message_name : String
  values : Array[(String, RawSignalValue)]
}

///|
/// Parse a supported DBC subset. Known metadata is skipped with diagnostics;
/// syntax that can change signal interpretation is rejected.
pub fn parse_dbc(source : String) -> Result[DbcDatabase, ParseError] {
  let messages : Array[MessageDefinition] = []
  let diagnostics : Array[ParseDiagnostic] = []
  let lines = source.split("\n")
  let mut line_number = 0
  let mut inside_namespace = false
  for raw_line in lines {
    line_number += 1
    let line = raw_line.to_owned().trim()
    if line.is_empty() {
      continue
    }
    let tokens = split_words(line)
    if tokens.length() == 0 {
      continue
    }
    if inside_namespace {
      if tokens[0] == "BS_:" || line == "BS_:" {
        inside_namespace = false
        diagnostics.push(ParseDiagnostic::{
          line: line_number,
          code: "BUS_TIMING_IGNORED",
          message: "bus timing metadata is not used by signal codecs",
        })
      } else if tokens[0] == "BO_" || tokens[0] == "SG_" {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "NS_ block ended without the required BS_: marker",
        })
      } else {
        for entry in tokens {
          if !known_namespace_entry(entry) {
            diagnostics.push(ParseDiagnostic::{
              line: line_number,
              code: "UNKNOWN_NAMESPACE_ENTRY",
              message: "unrecognized token in NS_ declaration list: " + entry,
            })
          }
        }
      }
      continue
    }
    if tokens[0] == "VERSION" {
      if !line.has_prefix("VERSION \"") || !line.has_suffix("\"") {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed VERSION declaration",
        })
      }
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "VERSION_IGNORED",
        message: "DBC version text does not affect signal layout",
      })
      continue
    }
    if tokens[0] == "NS_" {
      if tokens.length() != 2 || tokens[1] != ":" {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed NS_ header",
        })
      }
      inside_namespace = true
      continue
    }
    if tokens[0] == "BS_:" || line == "BS_:" {
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "BUS_TIMING_IGNORED",
        message: "bus timing metadata is not used by signal codecs",
      })
      continue
    }
    if tokens[0] == "BU_:" {
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "NODES_IGNORED",
        message: "node declarations do not alter this signal codec schema",
      })
      continue
    }
    if tokens[0] == "CM_" {
      if (!line.has_suffix("\"") && !line.has_suffix("\";")) ||
        !line.contains("\"") {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed CM_ comment declaration",
        })
      }
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "COMMENT_IGNORED",
        message: "comments are retained as parser diagnostics only, not in the codec model",
      })
      continue
    }
    if tokens[0] == "VAL_" {
      if tokens.length() < 5 || !line.has_suffix(";") {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed VAL_ choice declaration",
        })
      }
      let _frame_id = @string.parse_uint(tokens[1].to_string_view()) catch {
        _ =>
          return Err(ParseError::{
            line: line_number,
            kind: InvalidField,
            message: "invalid frame id in VAL_ declaration",
          })
      }
      let _raw_choice = @string.parse_int(tokens[3].to_string_view()) catch {
        _ =>
          return Err(ParseError::{
            line: line_number,
            kind: InvalidField,
            message: "VAL_ choice list must start with an integer raw value",
          })
      }
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "VALUE_TABLE_IGNORED",
        message: "choice labels do not alter raw or physical numeric codec values",
      })
      continue
    }
    if tokens[0] == "BA_DEF_" {
      if tokens.length() < 4 {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed BA_DEF_ attribute definition",
        })
      }
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "ATTRIBUTE_DEFINITION_IGNORED",
        message: "attribute definitions are not applied; BA_ assignments are rejected",
      })
      continue
    }
    if tokens[0] == "BA_DEF_DEF_" {
      if tokens.length() < 3 {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed BA_DEF_DEF_ default",
        })
      }
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "ATTRIBUTE_DEFAULT_IGNORED",
        message: "attribute defaults are not applied; BA_ assignments are rejected",
      })
      continue
    }
    if tokens[0] == "BA_" {
      if tokens.length() < 4 || !line.has_suffix(";") {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed BA_ attribute assignment",
        })
      }
      let attribute = unquote(tokens[1])
      if is_codec_irrelevant_attribute(attribute) {
        diagnostics.push(ParseDiagnostic::{
          line: line_number,
          code: "NON_LAYOUT_ATTRIBUTE_IGNORED",
          message: "non-layout timing/default attribute is ignored: " +
          attribute,
        })
        continue
      }
      return Err(ParseError::{
        line: line_number,
        kind: UnsupportedSemantic,
        message: "BA_ assignment is unsupported because it may change frame/signal interpretation: " +
        attribute,
      })
    }
    if tokens[0] == "SIG_VALTYPE_" {
      if tokens.length() != 5 || tokens[3] != ":" || !tokens[4].has_suffix(";") {
        return Err(ParseError::{
          line: line_number,
          kind: InvalidField,
          message: "malformed SIG_VALTYPE_ declaration",
        })
      }
      let value_text = tokens[4][0:tokens[4].length() - 1].to_string_view()
      let value_type = @string.parse_int(value_text) catch {
        _ =>
          return Err(ParseError::{
            line: line_number,
            kind: InvalidField,
            message: "invalid SIG_VALTYPE_ type code",
          })
      }
      if value_type != 0 {
        return Err(ParseError::{
          line: line_number,
          kind: UnsupportedSemantic,
          message: "floating-point SIG_VALTYPE_ changes raw signal interpretation",
        })
      }
      diagnostics.push(ParseDiagnostic::{
        line: line_number,
        code: "INTEGER_VALTYPE_IGNORED",
        message: "explicit integer signal type leaves codec interpretation unchanged",
      })
      continue
    }
    if tokens[0] == "BO_" {
      match parse_message(tokens, line_number) {
        Ok(message) => messages.push(message)
        Err(error) => return Err(error)
      }
    } else if tokens[0] == "SG_" {
      if messages.length() == 0 {
        return Err(ParseError::{
          line: line_number,
          kind: SignalWithoutMessage,
          message: "SG_ declaration appears before any BO_ message",
        })
      }
      if tokens.length() > 8 || (tokens.length() > 7 && tokens[7].contains(",")) {
        diagnostics.push(ParseDiagnostic::{
          line: line_number,
          code: "RECEIVERS_IGNORED",
          message: "additional receiver names are not stored by the codec schema",
        })
      }
      match parse_signal(tokens, line_number) {
        Ok(signal) => {
          let last = messages.length() - 1
          messages[last].signals.push(signal)
        }
        Err(error) => return Err(error)
      }
    } else {
      return Err(ParseError::{
        line: line_number,
        kind: UnsupportedSemantic,
        message: "unrecognized DBC declaration; refusing to guess whether it changes signal semantics",
      })
    }
  }
  if inside_namespace {
    return Err(ParseError::{
      line: line_number,
      kind: InvalidField,
      message: "NS_ block is missing its BS_: terminator",
    })
  }
  Ok(DbcDatabase::{ messages, diagnostics, })
}

///|
fn is_codec_irrelevant_attribute(attribute : String) -> Bool {
  attribute == "GenMsgCycleTime" ||
  attribute == "GenMsgCycleTimeFast" ||
  attribute == "GenMsgSendType" ||
  attribute == "GenMsgStartDelayTime" ||
  attribute == "GenMsgDelayTime" ||
  attribute == "GenMsgNrOfRepetitions" ||
  attribute == "GenSigStartValue" ||
  attribute == "GenSigInactiveValue"
}

///|
fn known_namespace_entry(entry : String) -> Bool {
  entry == "NS_DESC_" ||
  entry == "CM_" ||
  entry == "BA_DEF_" ||
  entry == "BA_" ||
  entry == "VAL_" ||
  entry == "CAT_DEF_" ||
  entry == "CAT_" ||
  entry == "FILTER" ||
  entry == "BA_DEF_DEF_" ||
  entry == "EV_DATA_" ||
  entry == "ENVVAR_DATA_" ||
  entry == "SGTYPE_" ||
  entry == "SGTYPE_VAL_" ||
  entry == "BA_DEF_SGTYPE_" ||
  entry == "BA_SGTYPE_" ||
  entry == "BA_DEF_REL_" ||
  entry == "BA_REL_" ||
  entry == "BA_DEF_DEF_REL_" ||
  entry == "BU_SG_REL_" ||
  entry == "BU_EV_REL_" ||
  entry == "BU_BO_REL_" ||
  entry == "SG_MUL_VAL_" ||
  entry == "SIG_VALTYPE_"
}

///|
fn split_words(line : StringView) -> Array[String] {
  let result : Array[String] = []
  let mut start = 0
  let mut inside_quote = false
  let mut index = 0
  while index < line.length() {
    match line.get_char(index) {
      Some('"') => inside_quote = !inside_quote
      Some(' ') | Some('\t') if !inside_quote => {
        if index > start {
          result.push(
            line.view(start_offset=start, end_offset=index).to_owned(),
          )
        }
        start = index + 1
      }
      _ => ()
    }
    index += 1
  }
  if start < line.length() {
    result.push(
      line.view(start_offset=start, end_offset=line.length()).to_owned(),
    )
  }
  result
}

///|
fn parse_message(
  tokens : Array[String],
  line : Int,
) -> Result[MessageDefinition, ParseError] {
  if tokens.length() != 5 {
    return Err(ParseError::{
      line,
      kind: InvalidMessage,
      message: "BO_ requires id, name, DLC, and exactly one transmitter token",
    })
  }
  let id_text = tokens[1].to_string_view()
  let id = @string.parse_uint(id_text) catch {
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "invalid BO_ message id",
      })
  }
  if id > 0x7FFU {
    return Err(ParseError::{
      line,
      kind: UnsupportedSemantic,
      message: "POC supports standard 11-bit CAN identifiers only",
    })
  }
  let name = tokens[2]
  if !name.has_suffix(":") || name.length() <= 1 {
    return Err(ParseError::{
      line,
      kind: InvalidField,
      message: "BO_ message name must end with ':'",
    })
  }
  let message_name = name[0:name.length() - 1].to_owned()
  let dlc = @string.parse_int(tokens[3].to_string_view()) catch {
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "invalid BO_ DLC",
      })
  }
  if dlc < 0 || dlc > 8 {
    return Err(ParseError::{
      line,
      kind: InvalidField,
      message: "classic CAN DLC must be between 0 and 8",
    })
  }
  Ok(MessageDefinition::{
    id,
    name: message_name,
    dlc,
    signals: [],
    source_line: line,
  })
}

///|
fn parse_signal(
  tokens : Array[String],
  line : Int,
) -> Result[SignalDefinition, ParseError] {
  if tokens.length() < 8 {
    return Err(ParseError::{
      line,
      kind: InvalidSignal,
      message: "SG_ requires name, layout, scale, range, and unit",
    })
  }
  if tokens[2] != ":" {
    return Err(ParseError::{
      line,
      kind: UnsupportedSemantic,
      message: "multiplexing markers are not supported",
    })
  }
  let name = tokens[1]
  let layout = tokens[3].to_string_view()
  let (start_text, remainder) = match layout.split_once("|") {
    Some(parts) => parts
    None =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "SG_ layout is missing '|'",
      })
  }
  let (length_text, endian_and_sign) = match remainder.split_once("@") {
    Some(parts) => parts
    None =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "SG_ layout is missing '@'",
      })
  }
  if endian_and_sign.length() < 2 {
    return Err(ParseError::{
      line,
      kind: InvalidField,
      message: "SG_ layout requires byte order and sign",
    })
  }
  let start_bit = @string.parse_int(start_text) catch {
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "invalid SG_ start bit",
      })
  }
  let bit_length = @string.parse_int(length_text) catch {
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "invalid SG_ bit length",
      })
  }
  let byte_order = match endian_and_sign.get_char(0) {
    Some('1') => Intel
    Some('0') => Motorola
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "byte order must be 1 (Intel) or 0 (Motorola)",
      })
  }
  let signedness = match endian_and_sign.get_char(1) {
    Some('+') => Unsigned
    Some('-') => Signed
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "signal sign must be '+' or '-'",
      })
  }
  let scale = match parse_pair(tokens[4], '(', ')', line, "scale") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let range = match parse_pair(tokens[5], '[', ']', line, "range") {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if tokens[6].has_prefix("\"") != tokens[6].has_suffix("\"") {
    return Err(ParseError::{
      line,
      kind: InvalidField,
      message: "SG_ unit string has unmatched quotes",
    })
  }
  if tokens.length() < 8 {
    return Err(ParseError::{
      line,
      kind: InvalidSignal,
      message: "SG_ requires at least one receiver token",
    })
  }
  let unit = unquote(tokens[6])
  Ok(SignalDefinition::{
    name,
    start_bit,
    bit_length,
    byte_order,
    signedness,
    factor: scale.0,
    offset: scale.1,
    minimum: Some(range.0),
    maximum: Some(range.1),
    unit,
    source_line: line,
  })
}

///|
fn parse_pair(
  token : String,
  opening : Char,
  closing : Char,
  line : Int,
  field : String,
) -> Result[(Double, Double), ParseError] {
  let view = token.to_string_view()
  if view.length() < 5 ||
    view.get_char(0) != Some(opening) ||
    view.get_char(view.length() - 1) != Some(closing) {
    return Err(ParseError::{
      line,
      kind: InvalidField,
      message: "invalid " + field + " pair",
    })
  }
  let inner = view.view(start_offset=1, end_offset=view.length() - 1)
  let separator = if opening == '(' { "," } else { "|" }
  let (left, right) = match inner.split_once(separator) {
    Some(parts) => parts
    None =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "invalid " + field + " pair separator",
      })
  }
  let first = @string.parse_double(left.trim()) catch {
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "invalid first value in " + field,
      })
  }
  let second = @string.parse_double(right.trim()) catch {
    _ =>
      return Err(ParseError::{
        line,
        kind: InvalidField,
        message: "invalid second value in " + field,
      })
  }
  Ok((first, second))
}

///|
fn unquote(token : String) -> String {
  if token.length() >= 2 && token.has_prefix("\"") && token.has_suffix("\"") {
    token[1:token.length() - 1].to_owned()
  } else {
    token
  }
}

///|
/// Validate message/signal uniqueness, scale/ranges, bit widths, DLC bounds,
/// and overlapping occupied bits. It does not mutate the parsed database.
pub fn validate_schema(database : DbcDatabase) -> Array[ValidationIssue] {
  let issues : Array[ValidationIssue] = []
  let mut i = 0
  while i < database.messages.length() {
    let message = database.messages[i]
    let mut j = 0
    while j < i {
      if database.messages[j].id == message.id {
        issues.push(ValidationIssue::{
          severity: Error,
          code: "DUPLICATE_MESSAGE_ID",
          message: "message id is duplicated",
          line: message.source_line,
        })
      }
      j += 1
    }
    if message.dlc < 0 || message.dlc > 8 {
      issues.push(ValidationIssue::{
        severity: Error,
        code: "INVALID_DLC",
        message: "classic CAN DLC must be in 0..8",
        line: message.source_line,
      })
    }
    if message.id > 0x7FFU {
      issues.push(ValidationIssue::{
        severity: Error,
        code: "MESSAGE_ID_OUT_OF_RANGE",
        message: "POC supports standard 11-bit CAN identifiers only",
        line: message.source_line,
      })
    }
    let mut s = 0
    while s < message.signals.length() {
      let signal = message.signals[s]
      if signal.bit_length < 1 || signal.bit_length > 64 {
        issues.push(ValidationIssue::{
          severity: Error,
          code: "INVALID_BIT_WIDTH",
          message: "signal bit width must be in 1..64",
          line: signal.source_line,
        })
      }
      if signal.factor.is_nan() ||
        signal.factor.is_inf() ||
        signal.factor == 0.0 ||
        signal.offset.is_nan() ||
        signal.offset.is_inf() {
        issues.push(ValidationIssue::{
          severity: Error,
          code: "INVALID_SCALE",
          message: "factor must be finite and nonzero; offset must be finite",
          line: signal.source_line,
        })
      }
      let invalid_range = match (signal.minimum, signal.maximum) {
        (Some(minimum), Some(maximum)) =>
          minimum > maximum ||
          minimum.is_nan() ||
          maximum.is_nan() ||
          minimum.is_inf() ||
          maximum.is_inf()
        (Some(minimum), None) => minimum.is_nan() || minimum.is_inf()
        (None, Some(maximum)) => maximum.is_nan() || maximum.is_inf()
        (None, None) => false
      }
      if invalid_range {
        issues.push(ValidationIssue::{
          severity: Error,
          code: "INVALID_RANGE",
          message: "signal range values must be finite and minimum <= maximum",
          line: signal.source_line,
        })
      }
      if !signal_fits_dlc(signal, message.dlc) {
        issues.push(ValidationIssue::{
          severity: Error,
          code: "SIGNAL_OUT_OF_DLC",
          message: "signal bits extend beyond the message DLC",
          line: signal.source_line,
        })
      }
      let mut previous = 0
      while previous < s {
        if message.signals[previous].name == signal.name {
          issues.push(ValidationIssue::{
            severity: Error,
            code: "DUPLICATE_SIGNAL_NAME",
            message: "signal name is duplicated within a message",
            line: signal.source_line,
          })
        }
        if signals_overlap(message.signals[previous], signal) {
          issues.push(ValidationIssue::{
            severity: Error,
            code: "SIGNAL_OVERLAP",
            message: "signal bit ranges overlap",
            line: signal.source_line,
          })
        }
        previous += 1
      }
      s += 1
    }
    i += 1
  }
  issues
}

///|
fn signal_fits_dlc(signal : SignalDefinition, dlc : Int) -> Bool {
  if signal.start_bit < 0 ||
    signal.bit_length < 1 ||
    signal.bit_length > 64 ||
    dlc < 0 ||
    dlc > 8 {
    return false
  }
  let mut bit = signal.start_bit
  let mut count = 0
  while count < signal.bit_length {
    if bit < 0 || bit >= dlc * 8 {
      return false
    }
    bit = next_signal_bit(bit, signal.byte_order)
    count += 1
  }
  true
}

///|
fn next_signal_bit(bit : Int, order : ByteOrder) -> Int {
  match order {
    Intel => bit + 1
    Motorola => if bit % 8 == 0 { bit + 15 } else { bit - 1 }
  }
}

///|
fn signals_overlap(left : SignalDefinition, right : SignalDefinition) -> Bool {
  let mut left_bit = left.start_bit
  let mut li = 0
  while li < left.bit_length {
    let mut right_bit = right.start_bit
    let mut ri = 0
    while ri < right.bit_length {
      if left_bit == right_bit {
        return true
      }
      right_bit = next_signal_bit(right_bit, right.byte_order)
      ri += 1
    }
    left_bit = next_signal_bit(left_bit, left.byte_order)
    li += 1
  }
  false
}

///|
/// Decode the signal's raw integer. Unsigned signals support the complete
/// UInt64 range; signed signals support the complete Int64 range.
pub fn decode_raw_signal(
  signal : SignalDefinition,
  payload : Bytes,
) -> Result[RawSignalValue, CodecError] {
  if signal.bit_length < 1 || signal.bit_length > 64 || signal.start_bit < 0 {
    return Err(InvalidBitLength)
  }
  if !signal_fits_dlc(signal, payload.length()) {
    return Err(FrameTooShort)
  }
  let mut raw : UInt64 = 0UL
  let mut bit = signal.start_bit
  let mut index = 0
  while index < signal.bit_length {
    let byte_index = bit / 8
    let bit_in_byte = bit % 8
    let byte = payload[byte_index].to_uint64()
    let bit_value = (byte >> bit_in_byte) & 1UL
    match signal.byte_order {
      Intel => raw = raw | (bit_value << index)
      Motorola => raw = (raw << 1) | bit_value
    }
    bit = next_signal_bit(bit, signal.byte_order)
    index += 1
  }
  match signal.signedness {
    Unsigned => Ok(UnsignedValue(raw))
    Signed => {
      let sign_bit = 1UL << (signal.bit_length - 1)
      if (raw & sign_bit) == 0UL {
        Ok(SignedValue(raw.reinterpret_as_int64()))
      } else if signal.bit_length == 64 {
        Ok(SignedValue(raw.reinterpret_as_int64()))
      } else {
        let mask = (1UL << signal.bit_length) - 1UL
        Ok(SignedValue((raw | UInt64::lnot(mask)).reinterpret_as_int64()))
      }
    }
  }
}

///|
/// Write a raw value into an existing payload, preserving all unrelated bits.
/// The caller supplies the correctly sized payload; use encode_message for
/// exact DLC validation and zero-initialized frames.
pub fn encode_raw_signal(
  signal : SignalDefinition,
  raw_value : RawSignalValue,
  payload : Bytes,
) -> Result[Bytes, CodecError] {
  if signal.bit_length < 1 || signal.bit_length > 64 || signal.start_bit < 0 {
    return Err(InvalidBitLength)
  }
  if !signal_fits_dlc(signal, payload.length()) {
    return Err(FrameTooShort)
  }
  let raw = match (signal.signedness, raw_value) {
    (Unsigned, UnsignedValue(value)) => {
      if signal.bit_length < 64 && value > (1UL << signal.bit_length) - 1UL {
        return Err(RawOutOfRange)
      }
      value
    }
    (Signed, SignedValue(value)) => {
      if !signed_value_fits(value, signal.bit_length) {
        return Err(RawOutOfRange)
      }
      value.reinterpret_as_uint64()
    }
    _ => return Err(RawSignednessMismatch)
  }
  let output = payload.to_array()
  let mut bit = signal.start_bit
  let mut index = 0
  while index < signal.bit_length {
    let source_index = match signal.byte_order {
      Intel => index
      Motorola => signal.bit_length - 1 - index
    }
    let bit_value = ((raw >> source_index) & 1UL).to_uint().reinterpret_as_int()
    let byte_index = bit / 8
    let bit_in_byte = bit % 8
    let current = output[byte_index].to_uint()
    let mask = 1U << bit_in_byte
    output[byte_index] = if bit_value == 1 {
      (current | mask).to_byte()
    } else {
      (current & (255U ^ mask)).to_byte()
    }
    bit = next_signal_bit(bit, signal.byte_order)
    index += 1
  }
  Ok(Bytes::from_array(output))
}

///|
fn signed_value_fits(value : Int64, width : Int) -> Bool {
  if width < 1 || width > 64 {
    return false
  }
  if width == 64 {
    return true
  }
  let magnitude : Int64 = 1L << (width - 1)
  value >= -magnitude && value < magnitude
}

///|
/// Decode and validate the exact message DLC before decoding every signal.
pub fn decode_message(
  message : MessageDefinition,
  payload : Bytes,
) -> Result[Array[(String, RawSignalValue)], CodecError] {
  if message.dlc < 0 || message.dlc > 8 || payload.length() != message.dlc {
    return Err(DlcMismatch)
  }
  let values : Array[(String, RawSignalValue)] = []
  for signal in message.signals {
    match decode_raw_signal(signal, payload) {
      Ok(value) => values.push((signal.name, value))
      Err(error) => return Err(error)
    }
  }
  Ok(values)
}

///|
/// Encode raw values into a zero-filled frame, validating exact count/name and
/// DLC. Values are supplied in the same order as `message.signals`.
pub fn encode_message(
  message : MessageDefinition,
  values : Array[RawSignalValue],
) -> Result[Bytes, CodecError] {
  if message.dlc < 0 || message.dlc > 8 {
    return Err(DlcMismatch)
  }
  if values.length() != message.signals.length() {
    return Err(RawSignednessMismatch)
  }
  let mut payload = Bytes::make(message.dlc, 0U.to_byte())
  let mut i = 0
  while i < message.signals.length() {
    match encode_raw_signal(message.signals[i], values[i], payload) {
      Ok(encoded) => payload = encoded
      Err(error) => return Err(error)
    }
    i += 1
  }
  Ok(payload)
}

///|
/// Convert a raw value to a physical number. Double conversion is exact only
/// through 2^53; wider integer signals return PhysicalPrecisionExceeded.
pub fn decode_physical(
  signal : SignalDefinition,
  raw : RawSignalValue,
) -> Result[Double, CodecError] {
  if !valid_scale(signal) {
    return Err(InvalidScale)
  }
  let raw_double = match (signal.signedness, raw) {
    (Unsigned, UnsignedValue(value)) => {
      if value > 9007199254740992UL {
        return Err(PhysicalPrecisionExceeded)
      }
      value.to_double()
    }
    (Signed, SignedValue(value)) => {
      if value > 9007199254740992L || value < -9007199254740992L {
        return Err(PhysicalPrecisionExceeded)
      }
      value.to_double()
    }
    _ => return Err(RawSignednessMismatch)
  }
  let physical = raw_double * signal.factor + signal.offset
  if !physical_value_in_range(signal, physical) {
    return Err(PhysicalOutOfRange)
  }
  Ok(physical)
}

///|
/// Convert a physical number to an exact integral raw value. There is no
/// implicit rounding or clamping: non-integral inverse scales are rejected.
pub fn encode_physical(
  signal : SignalDefinition,
  physical : Double,
  payload : Bytes,
) -> Result[Bytes, CodecError] {
  if !valid_scale(signal) {
    return Err(InvalidScale)
  }
  if physical.is_nan() || physical.is_inf() {
    return Err(InvalidPhysicalValue)
  }
  if !physical_value_in_range(signal, physical) {
    return Err(PhysicalOutOfRange)
  }
  let raw_double = (physical - signal.offset) / signal.factor
  if raw_double.is_nan() ||
    raw_double.is_inf() ||
    raw_double < -9007199254740992.0 ||
    raw_double > 9007199254740992.0 {
    return Err(PhysicalPrecisionExceeded)
  }
  if raw_double.trunc() != raw_double {
    return Err(PhysicalValueNotRepresentable)
  }
  let raw_value = match signal.signedness {
    Unsigned => {
      if raw_double < 0.0 {
        return Err(RawOutOfRange)
      }
      UnsignedValue(raw_double.to_uint64())
    }
    Signed => SignedValue(raw_double.to_int64())
  }
  encode_raw_signal(signal, raw_value, payload)
}

///|
fn valid_scale(signal : SignalDefinition) -> Bool {
  !signal.factor.is_nan() &&
  !signal.factor.is_inf() &&
  signal.factor != 0.0 &&
  !signal.offset.is_nan() &&
  !signal.offset.is_inf()
}

///|
fn physical_value_in_range(
  signal : SignalDefinition,
  physical : Double,
) -> Bool {
  match (signal.minimum, signal.maximum) {
    (Some(minimum), Some(maximum)) => physical >= minimum && physical <= maximum
    (Some(minimum), None) => physical >= minimum
    (None, Some(maximum)) => physical <= maximum
    (None, None) => true
  }
}

///|
/// Parse a DBC message by its frame ID.
pub fn find_message(database : DbcDatabase, id : UInt) -> MessageDefinition? {
  for message in database.messages {
    if message.id == id {
      return Some(message)
    }
  }
  None
}

///|
/// Decode a frame by message ID after validating the database.
pub fn decode_frame(
  database : DbcDatabase,
  frame_id : UInt,
  payload : Bytes,
) -> Result[DecodedFrame, FrameError] {
  let message = match find_message(database, frame_id) {
    Some(message) => message
    None => return Err(UnknownMessageId(frame_id))
  }
  for issue in validate_schema(database) {
    match issue.severity {
      Error => return Err(InvalidSchema(issue.code))
      Warning => ()
    }
  }
  match decode_message(message, payload) {
    Ok(values) =>
      Ok(DecodedFrame::{
        message_id: message.id,
        message_name: message.name,
        values,
      })
    Err(error) => Err(Codec(error))
  }
}

///|
/// Encode raw signal values by message and signal names.
/// Values must cover every signal exactly once; message signal order is not
/// exposed as an implicit caller requirement.
pub fn encode_frame(
  database : DbcDatabase,
  message_name : String,
  signal_values : Array[(String, RawSignalValue)],
) -> Result[Bytes, FrameError] {
  let mut message : MessageDefinition? = None
  for candidate in database.messages {
    if candidate.name == message_name {
      if message is Some(_) {
        return Err(InvalidSchema("DUPLICATE_MESSAGE_NAME"))
      }
      message = Some(candidate)
    }
  }
  let message = match message {
    Some(message) => message
    None => return Err(UnknownMessageName(message_name))
  }
  for issue in validate_schema(database) {
    match issue.severity {
      Error => return Err(InvalidSchema(issue.code))
      Warning => ()
    }
  }
  let ordered_values : Array[RawSignalValue] = []
  for signal in message.signals {
    let mut found : RawSignalValue? = None
    for (name, value) in signal_values {
      if name == signal.name {
        if found is Some(_) {
          return Err(DuplicateSignalValue(name))
        }
        found = Some(value)
      }
    }
    match found {
      Some(value) => ordered_values.push(value)
      None => return Err(MissingSignalValue(signal.name))
    }
  }
  for (name, _) in signal_values {
    let mut known = false
    for signal in message.signals {
      if signal.name == name {
        known = true
      }
    }
    if !known {
      return Err(UnknownSignalValue(name))
    }
  }
  match encode_message(message, ordered_values) {
    Ok(payload) => Ok(payload)
    Err(error) => Err(Codec(error))
  }
}
