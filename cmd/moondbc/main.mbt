///|
fn usage() -> String {
  "Usage:\n  moondbc validate <file.dbc> [--json]\n  moondbc inspect <file.dbc> [--json]\n  moondbc decode <file.dbc> --frame-id <id> --data <hex> [--extended] [--json]\n  moondbc decode-log <file.dbc> <candump.log>\n  moondbc encode <file.dbc> --message <name> [--physical] --signal <name=value> [--signal <name=value> ...]\n  moondbc --help\n\nHex data accepts A0BC or A0 BC. --frame-id is the on-bus ID; use --extended for 29-bit frames. Encode values are raw integers by default; pass --physical to encode physical values. JSON raw values are decimal strings to preserve 64-bit precision. validate --json emits machine-readable parser and schema diagnostics. decode-log reads classic candump -L records with 3-digit standard or 8-digit extended IDs and emits one NDJSON record per frame."
}

///|
async fn main {
  let argv = @env.args()
  if argv.length() < 2 || argv[1] == "--help" || argv[1] == "-h" {
    println(usage())
    if argv.length() < 2 {
      fail("missing command")
    }
    return
  }
  let command = argv[1]
  if command == "validate" {
    let json_mode = argv.length() == 4 && argv[3] == "--json"
    if argv.length() != 3 && !json_mode {
      fail(usage())
    }
    let database = read_database(argv[2])
    if !json_mode {
      print_diagnostics(database)
    }
    let issues = @lib.validate_schema(database)
    if json_mode {
      validate_database_json(database, issues)
      return
    }
    if issues.length() > 0 {
      for issue in issues {
        let severity = match issue.severity {
          @lib.Error => "ERROR"
          @lib.Warning => "WARNING"
        }
        println(
          "\{severity} \{issue.code} line \{issue.line}: \{issue.message}",
        )
      }
      fail("schema validation failed")
    }
    println(
      "valid: \{database.messages.length()} message(s), \{signal_count(database)} signal(s)",
    )
  } else if command == "inspect" {
    let json_mode = argv.length() == 4 && argv[3] == "--json"
    if argv.length() != 3 && !json_mode {
      fail(usage())
    }
    let database = read_database(argv[2])
    if !json_mode {
      print_diagnostics(database)
    }
    ensure_valid_schema(database)
    if json_mode {
      inspect_database_json(database)
    } else {
      inspect_database(database)
    }
  } else if command == "decode" {
    if argv.length() < 7 || argv[3] != "--frame-id" || argv[5] != "--data" {
      fail(usage())
    }
    let mut json_mode = false
    let mut extended = false
    let mut option_index = 7
    while option_index < argv.length() {
      if argv[option_index] == "--json" && !json_mode {
        json_mode = true
      } else if argv[option_index] == "--extended" && !extended {
        extended = true
      } else {
        fail("unknown or repeated decode option: {argv[option_index]}")
      }
      option_index += 1
    }
    let database = read_database(argv[2])
    if !json_mode {
      print_diagnostics(database)
    }
    ensure_valid_schema(database)
    let can_id = parse_frame_id(argv[4])
    let payload = parse_hex_payload(argv[6])
    let decoded = match
      @lib.decode_can_frame(database, can_id, extended, payload) {
      Ok(frame) => frame
      Err(error) => fail(frame_error_text(error))
    }
    if json_mode {
      decode_frame_json(database, decoded, payload)
      return
    }
    let (display_id, is_extended) = match
      @lib.dbc_id_to_can_id(decoded.message_id) {
      Ok(identity) => identity
      Err(_) => fail("internal error: invalid DBC frame identifier")
    }
    let frame_kind = if is_extended { "extended" } else { "standard" }
    println(
      "frame: id=\{display_id} type=\{frame_kind} name=\{decoded.message_name}",
    )
    let message = match @lib.find_message(database, decoded.message_id) {
      Some(message) => message
      None => fail("internal error: decoded message disappeared")
    }
    for (name, raw) in decoded.values {
      let signal = find_signal(message, name)
      let raw_text = raw_value_text(raw)
      match @lib.decode_physical(signal, raw) {
        Ok(physical) =>
          println(
            "  \{name}: raw=\{raw_text}, physical=\{physical} \{signal.unit}",
          )
        Err(@lib.PhysicalPrecisionExceeded) =>
          println(
            "  \{name}: raw=\{raw_text}, physical=unavailable (precision limit)",
          )
        Err(@lib.PhysicalOutOfRange) =>
          println(
            "  \{name}: raw=\{raw_text}, physical=unavailable (outside declared range)",
          )
        Err(_) => println("  \{name}: raw=\{raw_text}, physical=unavailable")
      }
      match @lib.lookup_value_label(database, decoded.message_id, name, raw) {
        Ok(label) => println("    label=\{label}")
        Err(_) => ()
      }
    }
  } else if command == "decode-log" {
    if argv.length() != 4 {
      fail("Usage: moondbc decode-log <file.dbc> <candump.log>")
    }
    let database = read_database(argv[2])
    ensure_valid_schema(database)
    decode_candump_log(database, argv[3])
  } else if command == "encode" {
    if argv.length() < 6 {
      fail(usage())
    }
    let database = read_database(argv[2])
    print_diagnostics(database)
    ensure_valid_schema(database)
    let mut message_name : String? = None
    let mut physical_mode = false
    let signal_assignments : Array[String] = []
    let mut index = 3
    while index < argv.length() {
      if argv[index] == "--message" && index + 1 < argv.length() {
        if message_name is Some(_) {
          fail("--message may only be provided once")
        }
        message_name = Some(argv[index + 1])
        index += 2
      } else if argv[index] == "--physical" {
        if physical_mode {
          fail("--physical may only be provided once")
        }
        physical_mode = true
        index += 1
      } else if argv[index] == "--signal" && index + 1 < argv.length() {
        signal_assignments.push(argv[index + 1])
        index += 2
      } else {
        fail("unexpected or incomplete encode argument: \{argv[index]}")
      }
    }
    let message_name = match message_name {
      Some(name) => name
      None => fail("encode requires --message <name>")
    }
    let message = find_message_by_name(database, message_name)
    let payload = if physical_mode {
      let mut payload = Bytes::make(message.dlc, 0U.to_byte())
      let seen : Array[String] = []
      for assignment in signal_assignments {
        let (name, physical) = parse_physical_assignment(assignment)
        if seen.contains(name) {
          fail("signal assigned more than once: \{name}")
        }
        seen.push(name)
        let signal = find_signal(message, name)
        payload = match @lib.encode_physical(signal, physical, payload) {
          Ok(encoded) => encoded
          Err(error) => fail(codec_error_text(error))
        }
      }
      if seen.length() != message.signals.length() {
        for signal in message.signals {
          if !seen.contains(signal.name) {
            fail("missing physical value for signal: \{signal.name}")
          }
        }
      }
      payload
    } else {
      let signal_values : Array[(String, @lib.RawSignalValue)] = []
      for assignment in signal_assignments {
        signal_values.push(
          parse_signal_assignment(database, Some(message_name), assignment),
        )
      }
      match @lib.encode_frame(database, message_name, signal_values) {
        Ok(payload) => payload
        Err(error) => fail(frame_error_text(error))
      }
    }
    println("payload=\{payload_to_hex(payload)}")
  } else {
    fail("unknown command: \{command}\n\{usage()}")
  }
}

///|
fn validate_database_json(
  database : @lib.DbcDatabase,
  issues : Array[@lib.ValidationIssue],
) -> Unit {
  let output = StringBuilder()
  let valid = if issues.length() == 0 { "true" } else { "false" }
  output.write_string("{\"valid\":")
  output.write_string(valid)
  output.write_string(",\"messages\":")
  output.write_string(database.messages.length().to_string())
  output.write_string(",\"signals\":")
  output.write_string(signal_count(database).to_string())
  output.write_string(",\"diagnostics\":[")
  let mut diagnostic_count = 0
  for diagnostic in database.diagnostics {
    if diagnostic_count > 0 {
      output.write_char(',')
    }
    output.write_string("{\"severity\":\"warning\",\"code\":")
    output.write_string(json_string(diagnostic.code))
    output.write_string(",\"line\":")
    output.write_string(diagnostic.line.to_string())
    output.write_string(",\"message\":")
    output.write_string(json_string(diagnostic.message))
    output.write_char('}')
    diagnostic_count += 1
  }
  for issue in issues {
    if diagnostic_count > 0 {
      output.write_char(',')
    }
    let severity = match issue.severity {
      @lib.Error => "error"
      @lib.Warning => "warning"
    }
    output.write_string("{\"severity\":")
    output.write_string(json_string(severity))
    output.write_string(",\"code\":")
    output.write_string(json_string(issue.code))
    output.write_string(",\"line\":")
    output.write_string(issue.line.to_string())
    output.write_string(",\"message\":")
    output.write_string(json_string(issue.message))
    output.write_char('}')
    diagnostic_count += 1
  }
  output.write_string("]}")
  println(output.to_string())
}

///|
fn inspect_database_json(database : @lib.DbcDatabase) -> Unit raise {
  let output = StringBuilder()
  output.write_string("{\"messages\":[")
  for message_index, message in database.messages {
    if message_index > 0 {
      output.write_char(',')
    }
    let (can_id, is_extended) = match @lib.dbc_id_to_can_id(message.id) {
      Ok(identity) => identity
      Err(_) => fail("internal error: invalid DBC frame identifier")
    }
    output.write_string(
      "{\"id\":\{can_id},\"extended\":\{is_extended},\"name\":",
    )
    output.write_string(json_string(message.name))
    output.write_string(",\"dlc\":\{message.dlc},\"signals\":[")
    for signal_index, signal in message.signals {
      if signal_index > 0 {
        output.write_char(',')
      }
      output.write_string("{\"name\":")
      output.write_string(json_string(signal.name))
      output.write_string(
        ",\"start_bit\":\{signal.start_bit},\"bit_length\":\{signal.bit_length},\"byte_order\":",
      )
      output.write_string(
        json_string(
          match signal.byte_order {
            @lib.Intel => "intel"
            @lib.Motorola => "motorola"
          },
        ),
      )
      output.write_string(",\"signedness\":")
      output.write_string(
        json_string(
          match signal.signedness {
            @lib.Unsigned => "unsigned"
            @lib.Signed => "signed"
          },
        ),
      )
      output.write_string(
        ",\"factor\":\{signal.factor},\"offset\":\{signal.offset},\"unit\":",
      )
      output.write_string(json_string(signal.unit))
      output.write_string(",\"multiplexing\":")
      match signal.multiplexing {
        @lib.NotMultiplexed => output.write_string("{\"role\":\"none\"}")
        @lib.Multiplexor => output.write_string("{\"role\":\"selector\"}")
        @lib.Multiplexed(value) =>
          output.write_string("{\"role\":\"branch\",\"value\":\{value}}")
      }
      output.write_string(",\"values\":[")
      let mut value_index = 0
      for description in database.value_descriptions {
        if description.message_id == message.id &&
          description.signal_name == signal.name {
          if value_index > 0 {
            output.write_char(',')
          }
          output.write_string("{\"raw\":")
          output.write_string(
            json_string(raw_value_text(description.raw_value)),
          )
          output.write_string(",\"label\":")
          output.write_string(json_string(description.label))
          output.write_char('}')
          value_index += 1
        }
      }
      output.write_string("]")
      output.write_string("}")
    }
    output.write_string("]}")
  }
  output.write_string("],\"comments\":[")
  for index, comment in database.comments {
    if index > 0 {
      output.write_char(',')
    }
    output.write_string("{\"target\":")
    output.write_string(json_string(comment_target_text(comment.target)))
    output.write_string(",\"text\":")
    output.write_string(json_string(comment.text))
    output.write_string(",\"line\":\{comment.source_line}}")
  }
  output.write_string("],\"diagnostics\":[")
  for index, diagnostic in database.diagnostics {
    if index > 0 {
      output.write_char(',')
    }
    output.write_string("{\"code\":")
    output.write_string(json_string(diagnostic.code))
    output.write_string(",\"line\":\{diagnostic.line},\"message\":")
    output.write_string(json_string(diagnostic.message))
    output.write_char('}')
  }
  output.write_string("]}")
  println(output.to_string())
}

///|
fn decode_frame_json(
  database : @lib.DbcDatabase,
  decoded : @lib.DecodedFrame,
  payload : Bytes,
) -> Unit raise {
  println(decode_frame_json_text(database, decoded, payload))
}

///|
fn decode_frame_json_text(
  database : @lib.DbcDatabase,
  decoded : @lib.DecodedFrame,
  payload : Bytes,
) -> String raise {
  let output = StringBuilder()
  let (can_id, is_extended) = match @lib.dbc_id_to_can_id(decoded.message_id) {
    Ok(identity) => identity
    Err(_) => fail("internal error: invalid DBC frame identifier")
  }
  output.write_string(
    "{\"frame_id\":\{can_id},\"extended\":\{is_extended},\"message\":",
  )
  output.write_string(json_string(decoded.message_name))
  output.write_string(",\"data\":")
  output.write_string(json_string(payload_to_hex(payload)))
  output.write_string(",\"signals\":[")
  let message = match @lib.find_message(database, decoded.message_id) {
    Some(found) => found
    None => fail("internal error: decoded message disappeared")
  }
  for index, (name, raw) in decoded.values {
    if index > 0 {
      output.write_char(',')
    }
    let signal = find_signal(message, name)
    output.write_string("{\"name\":")
    output.write_string(json_string(name))
    // Keep raw integers as decimal strings so UInt64 remains exact in every JSON consumer.
    output.write_string(",\"raw\":")
    output.write_string(json_string(raw_value_text(raw)))
    match @lib.decode_physical(signal, raw) {
      Ok(physical) =>
        output.write_string(
          ",\"physical\":\{physical},\"physical_status\":\"available\"",
        )
      Err(@lib.PhysicalPrecisionExceeded) =>
        output.write_string(
          ",\"physical\":null,\"physical_status\":\"precision_exceeded\"",
        )
      Err(@lib.PhysicalOutOfRange) =>
        output.write_string(
          ",\"physical\":null,\"physical_status\":\"outside_declared_range\"",
        )
      Err(_) =>
        output.write_string(
          ",\"physical\":null,\"physical_status\":\"unavailable\"",
        )
    }
    output.write_string(",\"unit\":")
    output.write_string(json_string(signal.unit))
    match @lib.lookup_value_label(database, decoded.message_id, name, raw) {
      Ok(label) => {
        output.write_string(",\"label\":")
        output.write_string(json_string(label))
      }
      Err(_) => ()
    }
    output.write_char('}')
  }
  output.write_string("]}")
  output.to_string()
}

///|
async fn decode_candump_log(database : @lib.DbcDatabase, path : String) -> Unit {
  let source = @fs.read_file(path).text() catch {
    _ => fail("cannot read candump log: \{path}")
  }
  let mut record_count = 0
  for line_index, raw_line in source.split("\n") {
    let line_number = line_index + 1
    let line = raw_line.to_owned().trim()
    if line.is_empty() {
      continue
    }
    let fields = split_whitespace(line.to_string_view())
    if fields.length() != 3 {
      fail(
        "candump line \{line_number}: expected '(timestamp) interface ID#DATA'",
      )
    }
    let timestamp_token = fields[0]
    if !timestamp_token.has_prefix("(") ||
      !timestamp_token.has_suffix(")") ||
      timestamp_token.length() < 3 {
      fail("candump line \{line_number}: invalid timestamp token")
    }
    let timestamp = timestamp_token[1:timestamp_token.length() - 1].to_owned()
    let interface = fields[1]
    let frame = fields[2]
    let separator = find_char_index(frame, '#')
    if separator < 0 ||
      separator == 0 ||
      frame[separator + 1:].to_owned().contains("#") {
      fail(
        "candump line \{line_number}: expected one ID#DATA separator; CAN FD is unsupported",
      )
    }
    let id_text = frame[0:separator]
    let extended = if id_text.length() == 3 {
      false
    } else if id_text.length() == 8 {
      true
    } else {
      fail(
        "candump line \{line_number}: ID must use 3 hex digits (standard) or 8 (extended)",
      )
    }
    let can_id = @string.parse_uint(id_text.to_string_view(), base=16) catch {
      _ => fail("candump line \{line_number}: invalid hexadecimal CAN ID")
    }
    let payload = parse_hex_payload(frame[separator + 1:].to_owned()) catch {
      _ => fail("candump line \{line_number}: malformed hexadecimal payload")
    }
    if payload.length() > 8 {
      fail("candump line \{line_number}: classic CAN payload exceeds 8 bytes")
    }
    let decoded = match
      @lib.decode_can_frame(database, can_id, extended, payload) {
      Ok(value) => value
      Err(error) =>
        fail("candump line \{line_number}: \{frame_error_text(error)}")
    }
    let output = StringBuilder()
    output.write_string("{\"line\":\{line_number},\"timestamp\":")
    output.write_string(json_string(timestamp))
    output.write_string(",\"interface\":")
    output.write_string(json_string(interface))
    output.write_string(",\"decoded\":")
    output.write_string(decode_frame_json_text(database, decoded, payload))
    output.write_char('}')
    println(output.to_string())
    record_count += 1
  }
  if record_count == 0 {
    fail("candump log contains no CAN records")
  }
}

///|
fn split_whitespace(text : StringView) -> Array[String] {
  let fields : Array[String] = []
  let mut start = -1
  let mut index = 0
  while index < text.length() {
    let char = match text.get_char(index) {
      Some(value) => value
      None => ' '
    }
    let whitespace = char == ' ' || char == '\t' || char == '\r'
    if whitespace {
      if start >= 0 {
        fields.push(text.view(start_offset=start, end_offset=index).to_owned())
        start = -1
      }
    } else if start < 0 {
      start = index
    }
    index += 1
  }
  if start >= 0 {
    fields.push(
      text.view(start_offset=start, end_offset=text.length()).to_owned(),
    )
  }
  fields
}

///|
fn find_char_index(text : String, needle : Char) -> Int {
  let mut index = 0
  for char in text.to_string_view() {
    if char == needle {
      return index
    }
    index += 1
  }
  -1
}

///|
fn comment_target_text(target : @lib.CommentTarget) -> String {
  match target {
    @lib.NetworkComment => "network"
    @lib.NodeComment(name) => "node:" + name
    @lib.MessageComment(id) => "message:" + id.to_string()
    @lib.SignalComment(id, name) => "signal:" + id.to_string() + ":" + name
  }
}

///|
fn json_string(value : String) -> String {
  let output = StringBuilder()
  output.write_char('"')
  for char in value.to_string_view() {
    match char {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      '\n' => output.write_string("\\n")
      '\r' => output.write_string("\\r")
      '\t' => output.write_string("\\t")
      '\b' => output.write_string("\\b")
      '\u{000C}' => output.write_string("\\f")
      c if c.to_int() < 0x20 => {
        let hex = hex_char(c.to_int() / 16)
        let low = hex_char(c.to_int() % 16)
        output.write_string("\\u00")
        output.write_char(hex)
        output.write_char(low)
      }
      _ => output.write_char(char)
    }
  }
  output.write_char('"')
  output.to_string()
}

///|
async fn read_database(path : String) -> @lib.DbcDatabase {
  let source = @fs.read_file(path).text() catch {
    _ => fail("cannot read DBC file from current working directory: \{path}")
  }
  match @lib.parse_dbc(source) {
    Ok(database) => database
    Err(error) =>
      fail(
        "parse error line \{error.line} [\{parse_error_kind_text(error.kind)}]: \{error.message}",
      )
  }
}

///|
fn ensure_valid_schema(database : @lib.DbcDatabase) -> Unit raise {
  let issues = @lib.validate_schema(database)
  if issues.length() > 0 {
    for issue in issues {
      println("ERROR \{issue.code} line \{issue.line}: \{issue.message}")
    }
    fail("schema validation failed")
  }
}

///|
fn print_diagnostics(database : @lib.DbcDatabase) -> Unit {
  for diagnostic in database.diagnostics {
    println(
      "WARNING \{diagnostic.code} line \{diagnostic.line}: \{diagnostic.message}",
    )
  }
}

///|
fn inspect_database(database : @lib.DbcDatabase) -> Unit raise {
  for message in database.messages {
    let (can_id, is_extended) = match @lib.dbc_id_to_can_id(message.id) {
      Ok(identity) => identity
      Err(_) => fail("internal error: invalid DBC frame identifier")
    }
    let frame_kind = if is_extended { "extended" } else { "standard" }
    println("BO_ \{can_id} (\{frame_kind}) \{message.name}: DLC=\{message.dlc}")
    for signal in message.signals {
      let order = match signal.byte_order {
        @lib.Intel => "Intel"
        @lib.Motorola => "Motorola"
      }
      let signedness = match signal.signedness {
        @lib.Unsigned => "unsigned"
        @lib.Signed => "signed"
      }
      println(
        "  SG_ \{signal.name}: start=\{signal.start_bit} length=\{signal.bit_length} endian=\{order} signedness=\{signedness} factor=\{signal.factor} offset=\{signal.offset} unit=\"\{signal.unit}\"",
      )
    }
  }
  for comment in database.comments {
    let target = match comment.target {
      @lib.NetworkComment => "CM_"
      @lib.NodeComment(name) => "CM_ BU_ " + name
      @lib.MessageComment(id) => "CM_ BO_ " + id.to_string()
      @lib.SignalComment(id, name) => "CM_ SG_ " + id.to_string() + " " + name
    }
    println(target + " \"" + escape_comment(comment.text) + "\";")
  }
}

///|
fn escape_comment(text : String) -> String {
  let result = StringBuilder()
  for char in text.to_string_view() {
    match char {
      '\\' => result.write_string("\\\\")
      '"' => result.write_string("\\\"")
      '\n' => result.write_string("\\n")
      '\r' => result.write_string("\\r")
      '\t' => result.write_string("\\t")
      _ => result.write_char(char)
    }
  }
  result.to_string()
}

///|
fn signal_count(database : @lib.DbcDatabase) -> Int {
  let mut count = 0
  for message in database.messages {
    count += message.signals.length()
  }
  count
}

///|
fn find_signal(
  message : @lib.MessageDefinition,
  name : String,
) -> @lib.SignalDefinition raise {
  for signal in message.signals {
    if signal.name == name {
      return signal
    }
  }
  fail("internal error: signal not found: \{name}")
}

///|
fn parse_frame_id(text : String) -> UInt raise {
  @string.parse_uint(text.to_string_view(), base=0) catch {
    _ => fail("invalid frame ID: \{text}")
  }
}

///|
fn parse_hex_payload(text : String) -> Bytes raise {
  let digits : Array[Char] = []
  for char in text.to_string_view() {
    if char != ' ' && char != '\t' && char != ':' && char != '_' {
      digits.push(char)
    }
  }
  let start = if digits.length() >= 2 &&
    digits[0] == '0' &&
    (digits[1] == 'x' || digits[1] == 'X') {
    2
  } else {
    0
  }
  if (digits.length() - start) % 2 != 0 {
    fail("frame data must contain complete hexadecimal bytes")
  }
  let bytes : Array[Byte] = []
  let mut index = start
  while index < digits.length() {
    let high = match hex_digit(digits[index]) {
      Some(value) => value
      None => fail("invalid hex digit in frame data")
    }
    let low = match hex_digit(digits[index + 1]) {
      Some(value) => value
      None => fail("invalid hex digit in frame data")
    }
    bytes.push((high * 16 + low).to_byte())
    index += 2
  }
  Bytes::from_array(bytes)
}

///|
fn hex_digit(char : Char) -> Int? {
  match char {
    '0' => Some(0)
    '1' => Some(1)
    '2' => Some(2)
    '3' => Some(3)
    '4' => Some(4)
    '5' => Some(5)
    '6' => Some(6)
    '7' => Some(7)
    '8' => Some(8)
    '9' => Some(9)
    'a' | 'A' => Some(10)
    'b' | 'B' => Some(11)
    'c' | 'C' => Some(12)
    'd' | 'D' => Some(13)
    'e' | 'E' => Some(14)
    'f' | 'F' => Some(15)
    _ => None
  }
}

///|
fn payload_to_hex(payload : Bytes) -> String {
  let output = StringBuilder()
  for byte in payload {
    let value = byte.to_uint()
    let high = value / 16U
    let low = value % 16U
    output.write_char(hex_char(high.reinterpret_as_int()))
    output.write_char(hex_char(low.reinterpret_as_int()))
  }
  output.to_string()
}

///|
fn hex_char(value : Int) -> Char {
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  ]
  digits[value]
}

///|
fn parse_signal_assignment(
  database : @lib.DbcDatabase,
  message_name : String?,
  assignment : String,
) -> (String, @lib.RawSignalValue) raise {
  let pieces = assignment.to_string_view().split("=")
  let name = match pieces.next() {
    Some(part) => part.to_owned()
    None => fail("signal must use NAME=RAW form: \{assignment}")
  }
  let value_text = match pieces.next() {
    Some(part) => part.to_owned()
    None => fail("signal must use NAME=RAW form: \{assignment}")
  }
  if pieces.next() is Some(_) {
    fail("signal must use NAME=RAW form: \{assignment}")
  }
  let message_name = match message_name {
    Some(name) => name
    None => fail("provide --message before --signal")
  }
  let message = find_message_by_name(database, message_name)
  let signal = find_signal(message, name)
  let value = match signal.signedness {
    @lib.Unsigned => {
      let raw = @string.parse_uint64(value_text.to_string_view(), base=0) catch {
        _ =>
          return (
            name,
            parse_value_label(database, message.id, name, value_text),
          )
      }
      @lib.UnsignedValue(raw)
    }
    @lib.Signed => {
      let raw = @string.parse_int64(value_text.to_string_view(), base=0) catch {
        _ =>
          return (
            name,
            parse_value_label(database, message.id, name, value_text),
          )
      }
      @lib.SignedValue(raw)
    }
  }
  (name, value)
}

///|
fn parse_value_label(
  database : @lib.DbcDatabase,
  message_id : UInt,
  signal_name : String,
  label : String,
) -> @lib.RawSignalValue raise {
  match @lib.lookup_raw_value(database, message_id, signal_name, label) {
    Ok(raw) => raw
    Err(@lib.ValueTableNotFound) =>
      fail("invalid raw integer or signal has no value table: \{label}")
    Err(@lib.ValueLabelNotFound(_)) =>
      fail("unknown value label for \{signal_name}: \{label}")
    Err(@lib.AmbiguousValueLabel(_)) =>
      fail("ambiguous value label for \{signal_name}: \{label}")
    Err(_) => fail("cannot resolve value label for \{signal_name}: \{label}")
  }
}

///|
fn parse_physical_assignment(assignment : String) -> (String, Double) raise {
  let pieces = assignment.to_string_view().split("=")
  let name = match pieces.next() {
    Some(part) => part.to_owned()
    None => fail("signal must use NAME=VALUE form: \{assignment}")
  }
  let value_text = match pieces.next() {
    Some(part) => part.to_owned()
    None => fail("signal must use NAME=VALUE form: \{assignment}")
  }
  if pieces.next() is Some(_) {
    fail("signal must use NAME=VALUE form: \{assignment}")
  }
  let value = @string.parse_double(value_text.to_string_view()) catch {
    _ => fail("invalid physical value: \{value_text}")
  }
  (name, value)
}

///|
fn find_message_by_name(
  database : @lib.DbcDatabase,
  name : String,
) -> @lib.MessageDefinition raise {
  for message in database.messages {
    if message.name == name {
      return message
    }
  }
  fail("unknown message name: \{name}")
}

///|
fn raw_value_text(value : @lib.RawSignalValue) -> String {
  match value {
    @lib.UnsignedValue(raw) => raw.to_string()
    @lib.SignedValue(raw) => raw.to_string()
  }
}

///|
fn parse_error_kind_text(kind : @lib.ParseErrorKind) -> String {
  match kind {
    @lib.InvalidField => "InvalidField"
    @lib.UnsupportedSyntax => "UnsupportedSyntax"
    @lib.UnsupportedSemantic => "UnsupportedSemantic"
    @lib.SignalWithoutMessage => "SignalWithoutMessage"
    @lib.InvalidMessage => "InvalidMessage"
    @lib.InvalidSignal => "InvalidSignal"
  }
}

///|
fn codec_error_text(error : @lib.CodecError) -> String {
  match error {
    @lib.InvalidBitLength => "invalid bit length"
    @lib.InvalidSignalRange => "invalid signal range"
    @lib.FrameTooShort => "frame is too short"
    @lib.DlcMismatch => "frame DLC does not match message DLC"
    @lib.RawSignednessMismatch => "raw value signedness does not match signal"
    @lib.RawOutOfRange => "raw value is outside the representable range"
    @lib.InvalidScale => "invalid factor or offset"
    @lib.InvalidPhysicalValue => "physical value is not finite"
    @lib.PhysicalValueNotRepresentable =>
      "physical value does not map to an exact raw integer"
    @lib.PhysicalPrecisionExceeded =>
      "physical conversion exceeds exact integer precision"
    @lib.PhysicalOutOfRange => "physical value is outside the declared range"
  }
}

///|
fn frame_error_text(error : @lib.FrameError) -> String {
  match error {
    @lib.UnknownMessageId(id) => "unknown message ID: \{id}"
    @lib.InvalidCanId(@lib.CanIdOutOfRange) =>
      "CAN ID exceeds the selected frame type range"
    @lib.InvalidCanId(@lib.InvalidDbcIdentifier) =>
      "invalid DBC frame identifier"
    @lib.UnknownMessageName(name) => "unknown message name: \{name}"
    @lib.InvalidSchema(code) => "invalid schema: \{code}"
    @lib.MissingSignalValue(name) => "missing raw value for signal: \{name}"
    @lib.DuplicateSignalValue(name) => "duplicate raw value for signal: \{name}"
    @lib.UnknownSignalValue(name) => "unknown raw value signal: \{name}"
    @lib.Codec(error) => codec_error_text(error)
  }
}
