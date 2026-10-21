///|
fn usage() -> String {
  "Usage:\n  moondbc validate <file.dbc>\n  moondbc inspect <file.dbc>\n  moondbc decode <file.dbc> --frame-id <id> --data <hex>\n  moondbc encode <file.dbc> --message <name> [--physical] --signal <name=value> [--signal <name=value> ...]\n  moondbc --help\n\nHex data accepts A0BC or A0 BC. Encode values are raw integers by default; pass --physical to encode physical values."
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
    if argv.length() != 3 {
      fail(usage())
    }
    let database = read_database(argv[2])
    print_diagnostics(database)
    let issues = @lib.validate_schema(database)
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
    if argv.length() != 3 {
      fail(usage())
    }
    let database = read_database(argv[2])
    print_diagnostics(database)
    ensure_valid_schema(database)
    inspect_database(database)
  } else if command == "decode" {
    if argv.length() != 7 || argv[3] != "--frame-id" || argv[5] != "--data" {
      fail(usage())
    }
    let database = read_database(argv[2])
    print_diagnostics(database)
    ensure_valid_schema(database)
    let frame_id = parse_frame_id(argv[4])
    let payload = parse_hex_payload(argv[6])
    let decoded = match @lib.decode_frame(database, frame_id, payload) {
      Ok(frame) => frame
      Err(error) => fail(frame_error_text(error))
    }
    println("frame: id=\{decoded.message_id} name=\{decoded.message_name}")
    let message = match @lib.find_message(database, frame_id) {
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
    }
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
fn inspect_database(database : @lib.DbcDatabase) -> Unit {
  for message in database.messages {
    println("BO_ \{message.id} \{message.name}: DLC=\{message.dlc}")
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
        _ => fail("invalid unsigned raw integer: \{value_text}")
      }
      @lib.UnsignedValue(raw)
    }
    @lib.Signed => {
      let raw = @string.parse_int64(value_text.to_string_view(), base=0) catch {
        _ => fail("invalid signed raw integer: \{value_text}")
      }
      @lib.SignedValue(raw)
    }
  }
  (name, value)
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
    @lib.UnknownMessageName(name) => "unknown message name: \{name}"
    @lib.InvalidSchema(code) => "invalid schema: \{code}"
    @lib.MissingSignalValue(name) => "missing raw value for signal: \{name}"
    @lib.DuplicateSignalValue(name) => "duplicate raw value for signal: \{name}"
    @lib.UnknownSignalValue(name) => "unknown raw value signal: \{name}"
    @lib.Codec(error) => codec_error_text(error)
  }
}
