///|
fn signal(
  name? : String = "Value",
  start_bit? : Int = 0,
  bit_length? : Int = 8,
  byte_order? : @moondbc.ByteOrder = Intel,
  signedness? : @moondbc.Signedness = Unsigned,
  factor? : Double = 1.0,
  offset? : Double = 0.0,
  minimum? : Double? = None,
  maximum? : Double? = None,
) -> @moondbc.SignalDefinition {
  @moondbc.SignalDefinition::{
    name,
    start_bit,
    bit_length,
    byte_order,
    signedness,
    factor,
    offset,
    minimum,
    maximum,
    unit: "",
    multiplexing: @moondbc.NotMultiplexed,
    source_line: 1,
  }
}

///|
test "parses multiple BO declarations and SG signals with scaling and units" {
  let parsed = @moondbc.parse_dbc(
    "BO_ 256 Example: 2 ECU\n SG_ IntelValue : 4|12@1+ (0.5,-1) [-1|2047] \"km/h\" ECU\nBO_ 257 Other: 2 ECU\n SG_ SignedValue : 0|12@1- (1,0) [-2048|2047] \"raw\" ECU",
  )
  match parsed {
    Err(_) => fail("valid minimum DBC did not parse")
    Ok(database) => {
      assert_eq(database.messages.length(), 2)
      assert_eq(database.messages[0].signals.length(), 1)
      assert_eq(database.messages[0].signals[0].start_bit, 4)
      assert_eq(database.messages[0].signals[0].bit_length, 12)
      assert_eq(database.messages[0].signals[0].factor, 0.5)
      assert_eq(database.messages[0].signals[0].offset, -1.0)
      assert_eq(database.messages[0].signals[0].unit, "km/h")
      assert_eq(database.messages[1].id, 257U)
    }
  }
}

///|
test "parser reports malformed fields with source line" {
  match @moondbc.parse_dbc("BO_ bad Example: 2 ECU\n") {
    Err(error) => {
      assert_eq(error.line, 1)
      match error.kind {
        @moondbc.InvalidField => ()
        _ => fail("wrong parse error kind")
      }
    }
    Ok(_) => fail("malformed id unexpectedly parsed")
  }
}

///|
test "parser retains single-level multiplexing markers" {
  match
    @moondbc.parse_dbc(
      "BO_ 1 Example: 1 ECU\n SG_ Value M : 0|1@1+ (1,0) [0|1] \"\" ECU",
    ) {
    Err(_) => fail("valid multiplexor marker did not parse")
    Ok(database) =>
      assert_true(
        database.messages[0].signals[0].multiplexing is @moondbc.Multiplexor,
      )
  }
}

///|
test "parser rejects signal before message" {
  match @moondbc.parse_dbc("SG_ Value : 0|1@1+ (1,0) [0|1] \"\" ECU") {
    Err(error) =>
      match error.kind {
        @moondbc.SignalWithoutMessage => ()
        _ => fail("wrong parse error kind")
      }
    Ok(_) => fail("orphan signal unexpectedly parsed")
  }
}

///|
test "parser accepts tabs and common DBC header declarations" {
  match
    @moondbc.parse_dbc(
      "BO_\t256\tTabbed:\t1 ECU\n\tSG_\tValue\t:\t0|8@1+\t(1,0)\t[0|255]\t\"\"\tECU",
    ) {
    Ok(database) => assert_eq(database.messages[0].signals.length(), 1)
    Err(_) => fail("tab-separated minimum declaration did not parse")
  }
  match
    @moondbc.parse_dbc(
      "VERSION \"1.0\"\nNS_ :\n CM_\n BA_DEF_\n VAL_\n BA_DEF_DEF_\nBS_:\nBU_: ECU\nBO_ 1 M: 1 ECU\n SG_ X : 0|8@1+ (1,0) [0|255] \"\" ECU",
    ) {
    Ok(database) => {
      assert_eq(database.messages.length(), 1)
      assert_eq(database.messages[0].signals.length(), 1)
      assert_true(database.diagnostics.length() >= 3)
    }
    Err(error) => fail("common DBC header failed on line \{error.line}")
  }
}

///|
test "parser accepts synthetic common-header fixture metadata" {
  let common_header = "VERSION \"Synthetic Release 1.0\"\nNS_ :\n    CM_\n    BA_DEF_\n    BA_\n    VAL_\n    BA_DEF_DEF_\nBS_:\nBU_: ECU SENSOR\n\nBO_ 256 CommonHeader: 2 ECU\n SG_ Speed : 4|12@1+ (0.5,-1) [-1|2047] \"km/h\" SENSOR\n SG_ Mode : 0|2@1+ (1,0) [0|3] \"\" SENSOR\nCM_ BO_ 256 \"Synthetic common-header fixture\";\nCM_ SG_ 256 Speed \"Synthetic speed signal\";\nVAL_ 256 Mode 0 \"Off\" 1 \"On\" 2 \"Hold\" 3 \"Fault\";\nBA_DEF_ \"BusType\" STRING ;\nBA_DEF_DEF_ \"BusType\" \"CAN\";\nBA_DEF_ BO_ \"GenMsgCycleTime\" INT 0 65535;\nBA_ \"GenMsgCycleTime\" BO_ 256 10;"
  match @moondbc.parse_dbc(common_header) {
    Ok(database) => {
      assert_eq(database.messages.length(), 1)
      assert_eq(database.messages[0].signals.length(), 2)
      assert_true(database.diagnostics.length() >= 6)
      assert_eq(database.comments.length(), 2)
      assert_eq(database.comments[0].text, "Synthetic common-header fixture")
      assert_eq(database.comments[1].text, "Synthetic speed signal")
      assert_eq(database.value_descriptions.length(), 4)
      match
        @moondbc.lookup_value_label(
          database,
          256U,
          "Mode",
          @moondbc.UnsignedValue(2UL),
        ) {
        Ok(label) => assert_eq(label, "Hold")
        Err(_) => fail("VAL_ raw value did not resolve to its label")
      }
      match @moondbc.lookup_raw_value(database, 256U, "Mode", "Fault") {
        Ok(@moondbc.UnsignedValue(raw)) => assert_eq(raw, 3UL)
        _ => fail("VAL_ label did not resolve to its raw value")
      }
      assert_true(@moondbc.validate_schema(database).length() == 0)
    }
    Err(error) => fail("common-header fixture failed on line \{error.line}")
  }
}

///|
test "parser retains scoped comments and unescapes DBC text" {
  let source = "BU_: ECU\nBO_ 256 Example: 1 ECU\n SG_ Value : 0|8@1+ (1,0) [0|255] \"\" ECU\nCM_ \"network says \\\"ready\\\"\\nnext\\\\path\";\nCM_ BU_ ECU \"node note\";\nCM_ BO_ 256 \"message note\";\nCM_ SG_ 256 Value \"signal note\";"
  match @moondbc.parse_dbc(source) {
    Err(error) => fail("scoped comment fixture failed at line \{error.line}")
    Ok(database) => {
      assert_eq(database.comments.length(), 4)
      assert_eq(database.comments[0].text, "network says \"ready\"\nnext\\path")
      match database.comments[0].target {
        @moondbc.NetworkComment => ()
        _ => fail("network comment target was not retained")
      }
      match database.comments[1].target {
        @moondbc.NodeComment(name) => assert_eq(name, "ECU")
        _ => fail("node comment target was not retained")
      }
      match database.comments[2].target {
        @moondbc.MessageComment(id) => assert_eq(id, 256U)
        _ => fail("message comment target was not retained")
      }
      match database.comments[3].target {
        @moondbc.SignalComment(id, name) => {
          assert_eq(id, 256U)
          assert_eq(name, "Value")
        }
        _ => fail("signal comment target was not retained")
      }
    }
  }
}

///|
test "parser rejects comments with missing references and malformed escapes" {
  match
    @moondbc.parse_dbc("BO_ 1 Example: 1 ECU\nCM_ SG_ 1 Missing \"orphan\";") {
    Err(error) => {
      assert_eq(error.line, 2)
      assert_true(error.message.contains("unknown"))
    }
    Ok(_) => fail("comment referencing an unknown signal was accepted")
  }
  match @moondbc.parse_dbc("CM_ \"unterminated;") {
    Err(error) => assert_eq(error.line, 1)
    Ok(_) => fail("unterminated comment was accepted")
  }
}

///|
test "VAL_ preserves signed and full-width unsigned raw values" {
  let source = "BO_ 1 Unsigned: 8 ECU\n SG_ U : 0|64@1+ (1,0) [0|18446744073709551615] \"\" ECU\nBO_ 2 Signed: 1 ECU\n SG_ S : 0|8@1- (1,0) [-128|127] \"\" ECU\nVAL_ 1 U 18446744073709551615 \"Maximum\";\nVAL_ 2 S -128 \"Minimum signed\";"
  match @moondbc.parse_dbc(source) {
    Err(error) =>
      fail("valid integer value tables failed on line \{error.line}")
    Ok(database) => {
      assert_eq(database.value_descriptions.length(), 2)
      match @moondbc.lookup_raw_value(database, 1U, "U", "Maximum") {
        Ok(@moondbc.UnsignedValue(raw)) => assert_eq(raw, 0xFFFFFFFFFFFFFFFFUL)
        _ => fail("UInt64 maximum was not preserved in the value table")
      }
      match
        @moondbc.lookup_value_label(
          database,
          2U,
          "S",
          @moondbc.SignedValue(-128L),
        ) {
        Ok(label) => assert_eq(label, "Minimum signed")
        Err(_) => fail("signed minimum did not resolve to its label")
      }
      assert_true(@moondbc.validate_schema(database).length() == 0)
    }
  }
}

///|
test "VAL_ rejects malformed pairs unknown signals and out-of-range values" {
  for
    source in [
      "BO_ 1 M: 1 ECU\n SG_ X : 0|8@1+ (1,0) [0|255] \"\" ECU\nVAL_ 1 X 0;", "BO_ 1 M: 1 ECU\n SG_ X : 0|8@1+ (1,0) [0|255] \"\" ECU\nVAL_ 1 Missing 0 \"Zero\";",
      "BO_ 1 M: 1 ECU\n SG_ X : 0|2@1+ (1,0) [0|3] \"\" ECU\nVAL_ 1 X 4 \"Too high\";",
    ] {
    match @moondbc.parse_dbc(source) {
      Err(error) =>
        match error.kind {
          @moondbc.InvalidField => ()
          _ => fail("invalid VAL_ table had the wrong error category")
        }
      Ok(_) => fail("invalid VAL_ table was silently accepted")
    }
  }
}

///|
test "VAL_ duplicate raw values and labels are reported by schema validation" {
  let source = "BO_ 1 M: 1 ECU\n SG_ X : 0|2@1+ (1,0) [0|3] \"\" ECU\nVAL_ 1 X 1 \"Same\" 1 \"Other\" 2 \"Same\";"
  match @moondbc.parse_dbc(source) {
    Err(_) => fail("syntactically valid duplicate choices did not parse")
    Ok(database) => {
      assert_true(
        has_issue(@moondbc.validate_schema(database), "DUPLICATE_VALUE_RAW"),
      )
      assert_true(
        has_issue(@moondbc.validate_schema(database), "AMBIGUOUS_VALUE_LABEL"),
      )
    }
  }
}

///|
test "parser preserves quoted unit spaces and diagnoses extra receivers" {
  match
    @moondbc.parse_dbc(
      "BO_ 1 M: 1 ECU\n SG_ X : 0|8@1+ (1,0) [0|255] \"kilometers per hour\" ECU_A, ECU_B",
    ) {
    Ok(database) => {
      assert_eq(database.messages[0].signals[0].unit, "kilometers per hour")
      assert_true(database.diagnostics[0].code == "RECEIVERS_IGNORED")
    }
    Err(_) => fail("quoted unit or receiver list did not parse")
  }
}

///|
test "parser rejects frame-format attributes and float signals" {
  let semantic_dbc = "VERSION \"1.0\"\nNS_ :\n BA_\nBS_:\nBU_: ECU\nBO_ 256 ExtendedFrame: 8 ECU\n SG_ Value : 0|8@1+ (1,0) [0|255] \"\" ECU\nBA_ \"VFrameFormat\" BO_ 256 1;"
  match @moondbc.parse_dbc(semantic_dbc) {
    Err(error) =>
      match error.kind {
        @moondbc.UnsupportedSemantic => ()
        _ => fail("frame-format attribute had wrong error classification")
      }
    Ok(_) => fail("frame-format attribute was silently ignored")
  }
  match @moondbc.parse_dbc("BO_ 1 M: 8 ECU\nSIG_VALTYPE_ 1 Value : 1;") {
    Err(error) =>
      match error.kind {
        @moondbc.UnsupportedSemantic => ()
        _ => fail("floating signal type had wrong error classification")
      }
    Ok(_) => fail("floating signal type was silently interpreted as integer")
  }
}

///|
test "single-level multiplexed fixture validates and decodes active signals" {
  let source = "VERSION \"\"\nNS_ :\nBS_:\nBU_: ECU\nBO_ 700 Mux: 2 ECU\n SG_ Mode M : 0|2@1+ (1,0) [0|3] \"\" ECU\n SG_ Base : 2|6@1+ (1,0) [0|63] \"\" ECU\n SG_ A m1 : 8|8@1+ (1,0) [0|255] \"\" ECU\n SG_ B m2 : 8|8@1+ (1,0) [0|255] \"\" ECU"
  let database = match @moondbc.parse_dbc(source) {
    Ok(database) => database
    Err(error) => fail("multiplexed DBC failed to parse on line \{error.line}")
  }
  let issues = @moondbc.validate_schema(database)
  for issue in issues {
    if issue.severity is @moondbc.Error {
      fail("valid disjoint multiplexed branches rejected: \{issue.code}")
    }
  }
  match
    @moondbc.decode_frame(database, 700U, [0x01U.to_byte(), 0x2AU.to_byte()]) {
    Ok(frame) => {
      assert_eq(frame.values.length(), 3)
      assert_eq(frame.values[0].0, "Mode")
      assert_eq(frame.values[1].0, "Base")
      assert_eq(frame.values[2].0, "A")
      match frame.values[2].1 {
        @moondbc.UnsignedValue(value) => assert_eq(value, 42UL)
        _ => fail("branch A raw value was not unsigned")
      }
    }
    Err(_) => fail("branch 1 frame failed to decode")
  }
  match
    @moondbc.decode_frame(database, 700U, [0x02U.to_byte(), 0x63U.to_byte()]) {
    Ok(frame) => {
      assert_eq(frame.values.length(), 3)
      assert_eq(frame.values[2].0, "B")
      match frame.values[2].1 {
        @moondbc.UnsignedValue(value) => assert_eq(value, 99UL)
        _ => fail("branch B raw value was not unsigned")
      }
    }
    Err(_) => fail("branch 2 frame failed to decode")
  }
}

///|
test "single-level multiplexed encoding requires exactly active signal values" {
  let source = "BO_ 700 Mux: 2 ECU\n SG_ Mode M : 0|2@1+ (1,0) [0|3] \"\" ECU\n SG_ Base : 2|6@1+ (1,0) [0|63] \"\" ECU\n SG_ A m1 : 8|8@1+ (1,0) [0|255] \"\" ECU\n SG_ B m2 : 8|8@1+ (1,0) [0|255] \"\" ECU"
  let database = match @moondbc.parse_dbc(source) {
    Ok(database) => database
    Err(_) => fail("multiplexed DBC failed to parse")
  }
  match
    @moondbc.encode_frame(database, "Mux", [
      ("Mode", @moondbc.UnsignedValue(1UL)),
      ("Base", @moondbc.UnsignedValue(0UL)),
      ("A", @moondbc.UnsignedValue(42UL)),
    ]) {
    Ok(payload) => assert_eq(payload, [0x01U.to_byte(), 0x2AU.to_byte()])
    Err(_) => fail("active branch values did not encode")
  }
  match
    @moondbc.encode_frame(database, "Mux", [
      ("Mode", @moondbc.UnsignedValue(1UL)),
      ("Base", @moondbc.UnsignedValue(0UL)),
      ("A", @moondbc.UnsignedValue(42UL)),
      ("B", @moondbc.UnsignedValue(99UL)),
    ]) {
    Err(@moondbc.UnknownSignalValue(_)) => ()
    _ => fail("inactive branch value was not rejected")
  }
}

///|
test "nested multiplexing marker is explicitly unsupported" {
  match
    @moondbc.parse_dbc(
      "BO_ 1 M: 1 ECU\n SG_ Value m1M : 0|1@1+ (1,0) [0|1] \"\" ECU",
    ) {
    Err(error) => assert_true(error.kind is @moondbc.UnsupportedSemantic)
    Ok(_) => fail("nested multiplexing marker was silently accepted")
  }
}

///|
test "CAN ID conversion preserves standard and extended boundaries" {
  match @moondbc.can_id_to_dbc_id(0x7FFU, false) {
    Ok(id) => assert_eq(id, 0x7FFU)
    Err(_) => fail("maximum standard ID rejected")
  }
  match @moondbc.can_id_to_dbc_id(0x1FFFFFFFU, true) {
    Ok(id) => assert_eq(id, 0x9FFFFFFFU)
    Err(_) => fail("maximum extended ID rejected")
  }
  match @moondbc.dbc_id_to_can_id(0x7FFU) {
    Ok(identity) => assert_eq(identity, (0x7FFU, false))
    Err(_) => fail("standard DBC ID did not round-trip")
  }
  match @moondbc.dbc_id_to_can_id(0x9FFFFFFFU) {
    Ok(identity) => assert_eq(identity, (0x1FFFFFFFU, true))
    Err(_) => fail("extended DBC ID did not round-trip")
  }
  match @moondbc.can_id_to_dbc_id(0x800U, false) {
    Err(@moondbc.CanIdOutOfRange) => ()
    _ => fail("out-of-range standard ID was accepted")
  }
  match @moondbc.can_id_to_dbc_id(0x20000000U, true) {
    Err(@moondbc.CanIdOutOfRange) => ()
    _ => fail("out-of-range extended ID was accepted")
  }
  match @moondbc.dbc_id_to_can_id(0x800U) {
    Err(@moondbc.InvalidDbcIdentifier) => ()
    _ => fail("unmarked 12-bit DBC identifier was accepted")
  }
}

///|
test "standard and extended messages with the same bus ID remain distinct" {
  let source = "BO_ 291 StandardFrame: 1 ECU\n SG_ Value : 0|8@1+ (1,0) [0|255] \"\" ECU\nBO_ 2147483939 ExtendedFrame: 1 ECU\n SG_ Value : 0|8@1+ (1,0) [0|255] \"\" ECU"
  let database = match @moondbc.parse_dbc(source) {
    Ok(database) => database
    Err(_) => fail("standard and DBC-marked extended IDs should parse")
  }
  assert_eq(@moondbc.validate_schema(database).length(), 0)
  let standard = match
    @moondbc.decode_can_frame(
      database,
      291U,
      false,
      Bytes::from_array([b'\x11']),
    ) {
    Ok(frame) => frame
    Err(_) => fail("standard frame failed to select standard definition")
  }
  let extended = match
    @moondbc.decode_can_frame(
      database,
      291U,
      true,
      Bytes::from_array([b'\x22']),
    ) {
    Ok(frame) => frame
    Err(_) => fail("extended frame failed to select extended definition")
  }
  assert_eq(standard.message_name, "StandardFrame")
  assert_eq(extended.message_name, "ExtendedFrame")
  assert_true(standard.message_id != extended.message_id)
  match
    @moondbc.decode_can_frame(
      database,
      2048U,
      false,
      Bytes::from_array([b'\x11']),
    ) {
    Err(@moondbc.InvalidCanId(@moondbc.CanIdOutOfRange)) => ()
    _ => fail("out-of-range standard ID was not rejected")
  }
}

///|
test "Intel cross-byte decoding returns raw 0xBCA" {
  match
    @moondbc.decode_raw_signal(
      signal(start_bit=4, bit_length=12),
      Bytes::from_array([b'\xA0', b'\xBC']),
    ) {
    Ok(@moondbc.UnsignedValue(raw)) => assert_eq(raw, 0xBCAUL)
    _ => fail("Intel payload did not decode as unsigned 0xBCA")
  }
}

///|
test "Intel cross-byte encoding returns A0 BC" {
  match
    @moondbc.encode_raw_signal(
      signal(start_bit=4, bit_length=12),
      @moondbc.UnsignedValue(0xBCAUL),
      Bytes::make(2, 0U.to_byte()),
    ) {
    Ok(bytes) => assert_eq(bytes, Bytes::from_array([b'\xA0', b'\xBC']))
    Err(_) => fail("valid Intel value was rejected")
  }
}

///|
test "field encoding preserves bits outside the signal" {
  match
    @moondbc.encode_raw_signal(
      signal(start_bit=4, bit_length=12),
      @moondbc.UnsignedValue(0xBCAUL),
      Bytes::from_array([b'\x0F', b'\x00']),
    ) {
    Ok(bytes) => assert_eq(bytes, Bytes::from_array([b'\xAF', b'\xBC']))
    Err(_) => fail("valid field update failed")
  }
}

///|
test "Motorola sawtooth cross-byte decoding returns raw 0xABC" {
  match
    @moondbc.decode_raw_signal(
      signal(start_bit=7, bit_length=12, byte_order=Motorola),
      Bytes::from_array([b'\xAB', b'\xC0']),
    ) {
    Ok(@moondbc.UnsignedValue(raw)) => assert_eq(raw, 0xABCUL)
    _ => fail("Motorola payload did not decode as unsigned 0xABC")
  }
}

///|
test "Motorola sawtooth cross-byte encoding returns AB C0" {
  match
    @moondbc.encode_raw_signal(
      signal(start_bit=7, bit_length=12, byte_order=Motorola),
      @moondbc.UnsignedValue(0xABCUL),
      Bytes::make(2, 0U.to_byte()),
    ) {
    Ok(bytes) => assert_eq(bytes, Bytes::from_array([b'\xAB', b'\xC0']))
    Err(_) => fail("valid Motorola value was rejected")
  }
}

///|
test "Motorola unsigned widths 1 7 8 9 12 16 32 63 64 round-trip" {
  let widths = [1, 7, 8, 9, 12, 16, 32, 63, 64]
  for width in widths {
    let value = unsigned_max(width)
    let definition = signal(start_bit=7, bit_length=width, byte_order=Motorola)
    match
      @moondbc.encode_raw_signal(
        definition,
        @moondbc.UnsignedValue(value),
        Bytes::make(8, 0U.to_byte()),
      ) {
      Err(_) => fail("Motorola unsigned width failed to encode: {width}")
      Ok(payload) =>
        match @moondbc.decode_raw_signal(definition, payload) {
          Ok(@moondbc.UnsignedValue(decoded)) => assert_eq(decoded, value)
          _ => fail("Motorola unsigned width failed to decode: {width}")
        }
    }
  }
}

///|
test "Motorola signed widths round-trip minimum and maximum" {
  let widths = [1, 7, 8, 9, 12, 16, 32, 63, 64]
  for width in widths {
    let (minimum, maximum) = signed_bounds(width)
    let definition = signal(
      start_bit=7,
      bit_length=width,
      byte_order=Motorola,
      signedness=Signed,
    )
    for value in [minimum, maximum] {
      match
        @moondbc.encode_raw_signal(
          definition,
          @moondbc.SignedValue(value),
          Bytes::make(8, 0U.to_byte()),
        ) {
        Err(_) => fail("Motorola signed width failed to encode: {width}")
        Ok(payload) =>
          match @moondbc.decode_raw_signal(definition, payload) {
            Ok(@moondbc.SignedValue(decoded)) => assert_eq(decoded, value)
            _ => fail("Motorola signed width failed to decode: {width}")
          }
      }
    }
  }
}

///|
test "Motorola invalid start and frame overflow are rejected" {
  let payload = Bytes::make(8, 0U.to_byte())
  assert_true(
    @moondbc.decode_raw_signal(
      signal(start_bit=64, bit_length=1, byte_order=Motorola),
      payload,
    )
    is Err(_),
  )
  assert_true(
    @moondbc.decode_raw_signal(
      signal(start_bit=0, bit_length=2, byte_order=Motorola),
      Bytes::make(1, 0U.to_byte()),
    )
    is Err(_),
  )
}

///|
test "signed 12-bit minimum uses two's complement" {
  match
    @moondbc.decode_raw_signal(
      signal(bit_length=12, signedness=Signed),
      Bytes::from_array([b'\x00', b'\x08']),
    ) {
    Ok(@moondbc.SignedValue(raw)) => assert_eq(raw, -2048L)
    _ => fail("signed minimum was decoded incorrectly")
  }
}

///|
test "signed 12-bit maximum encodes and decodes" {
  let definition = signal(bit_length=12, signedness=Signed)
  let payload = Bytes::from_array([b'\xFF', b'\x07'])
  match @moondbc.decode_raw_signal(definition, payload) {
    Ok(@moondbc.SignedValue(raw)) => assert_eq(raw, 2047L)
    _ => fail("signed maximum was decoded incorrectly")
  }
  match
    @moondbc.encode_raw_signal(
      definition,
      @moondbc.SignedValue(2047L),
      Bytes::make(2, 0U.to_byte()),
    ) {
    Ok(encoded) => assert_eq(encoded, payload)
    Err(_) => fail("signed maximum failed to encode")
  }
}

///|
test "unsigned 64-bit high bit is preserved" {
  let payload = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x80',
  ])
  match @moondbc.decode_raw_signal(signal(bit_length=64), payload) {
    Ok(@moondbc.UnsignedValue(raw)) => assert_eq(raw, 0x8000000000000000UL)
    _ => fail("unsigned 64-bit top bit was lost")
  }
}

///|
test "unsigned 64-bit maximum encodes without truncation" {
  let value = 0xFFFFFFFFFFFFFFFFUL
  match
    @moondbc.encode_raw_signal(
      signal(bit_length=64),
      @moondbc.UnsignedValue(value),
      Bytes::make(8, 0U.to_byte()),
    ) {
    Ok(bytes) =>
      match @moondbc.decode_raw_signal(signal(bit_length=64), bytes) {
        Ok(@moondbc.UnsignedValue(decoded)) => assert_eq(decoded, value)
        _ => fail("unsigned 64-bit maximum did not decode")
      }
    Err(_) => fail("unsigned 64-bit maximum was rejected")
  }
}

///|
test "raw UInt64 remains exact beyond Double integer precision" {
  let value = 9007199254740993UL
  let definition = signal(bit_length=64)
  match
    @moondbc.encode_raw_signal(
      definition,
      @moondbc.UnsignedValue(value),
      Bytes::make(8, 0U.to_byte()),
    ) {
    Err(_) => fail("raw value beyond 2^53 was rejected")
    Ok(payload) =>
      match @moondbc.decode_raw_signal(definition, payload) {
        Ok(@moondbc.UnsignedValue(decoded)) => assert_eq(decoded, value)
        _ => fail("raw value beyond 2^53 lost integer precision")
      }
  }
  assert_true(
    @moondbc.decode_physical(definition, @moondbc.UnsignedValue(value))
    is Err(@moondbc.PhysicalPrecisionExceeded),
  )
  assert_true(
    @moondbc.decode_physical(
      definition,
      @moondbc.UnsignedValue(9007199254740992UL),
    )
    is Ok(_),
  )
}

///|
test "signed 64-bit minimum round-trips" {
  let value = -9223372036854775808L
  let definition = signal(bit_length=64, signedness=Signed)
  match
    @moondbc.encode_raw_signal(
      definition,
      @moondbc.SignedValue(value),
      Bytes::make(8, 0U.to_byte()),
    ) {
    Ok(bytes) =>
      match @moondbc.decode_raw_signal(definition, bytes) {
        Ok(@moondbc.SignedValue(decoded)) => assert_eq(decoded, value)
        _ => fail("signed 64-bit minimum did not decode")
      }
    Err(_) => fail("signed 64-bit minimum was rejected")
  }
}

///|
test "raw overflow and signedness mismatch are rejected" {
  let definition = signal(bit_length=9)
  assert_true(
    @moondbc.encode_raw_signal(
      definition,
      @moondbc.UnsignedValue(512UL),
      Bytes::make(2, 0U.to_byte()),
    )
    is Err(_),
  )
  assert_true(
    @moondbc.encode_raw_signal(
      definition,
      @moondbc.SignedValue(1L),
      Bytes::make(2, 0U.to_byte()),
    )
    is Err(_),
  )
}

///|
test "short signal payload and incorrect message DLC are rejected" {
  assert_true(
    @moondbc.decode_raw_signal(
      signal(start_bit=4, bit_length=12),
      Bytes::make(1, 0U.to_byte()),
    )
    is Err(_),
  )
  let message = @moondbc.MessageDefinition::{
    id: 1U,
    name: "M",
    dlc: 2,
    signals: [],
    source_line: 1,
  }
  assert_true(
    @moondbc.decode_message(message, Bytes::make(1, 0U.to_byte())) is Err(_),
  )
  assert_true(
    @moondbc.decode_message(message, Bytes::make(3, 0U.to_byte())) is Err(_),
  )
}

///|
test "physical conversion requires factor and offset and round-trips" {
  let definition = signal(start_bit=4, bit_length=12, factor=0.5, offset=-1.0)
  match @moondbc.decode_physical(definition, @moondbc.UnsignedValue(0xBCAUL)) {
    Ok(value) => assert_eq(value, 1508.0)
    Err(_) => fail("physical conversion failed")
  }
  match
    @moondbc.encode_physical(definition, 1508.0, Bytes::make(2, 0U.to_byte())) {
    Ok(bytes) => assert_eq(bytes, Bytes::from_array([b'\xA0', b'\xBC']))
    Err(_) => fail("representable physical value was rejected")
  }
}

///|
test "non-integral inverse scale and physical range violations are rejected" {
  let definition = signal(
    bit_length=8,
    factor=2.0,
    minimum=Some(0.0),
    maximum=Some(100.0),
  )
  assert_true(
    @moondbc.encode_physical(definition, 3.0, Bytes::make(1, 0U.to_byte()))
    is Err(_),
  )
  assert_true(
    @moondbc.encode_physical(definition, 102.0, Bytes::make(1, 0U.to_byte()))
    is Err(_),
  )
}

///|
test "physical encode and decode both enforce declared range" {
  let definition = signal(bit_length=8, minimum=Some(0.0), maximum=Some(100.0))
  assert_true(
    @moondbc.encode_physical(definition, 101.0, Bytes::make(1, 0U.to_byte()))
    is Err(@moondbc.PhysicalOutOfRange),
  )
  assert_true(
    @moondbc.decode_physical(definition, @moondbc.UnsignedValue(101UL))
    is Err(@moondbc.PhysicalOutOfRange),
  )
}

///|
test "validator catches duplicate IDs signal names overlap and width" {
  let first = signal(name="A", start_bit=0, bit_length=8)
  let second = signal(name="A", start_bit=4, bit_length=4)
  let message1 = @moondbc.MessageDefinition::{
    id: 1U,
    name: "M1",
    dlc: 1,
    signals: [first, second],
    source_line: 1,
  }
  let message2 = @moondbc.MessageDefinition::{
    id: 1U,
    name: "M2",
    dlc: 1,
    signals: [signal(bit_length=65)],
    source_line: 3,
  }
  let issues = @moondbc.validate_schema(@moondbc.DbcDatabase::{
    messages: [message1, message2],
    value_descriptions: [],
    comments: [],
    diagnostics: [],
  })
  assert_true(has_issue(issues, "DUPLICATE_MESSAGE_ID"))
  assert_true(has_issue(issues, "DUPLICATE_SIGNAL_NAME"))
  assert_true(has_issue(issues, "SIGNAL_OVERLAP"))
  assert_true(has_issue(issues, "INVALID_BIT_WIDTH"))
}

///|
test "validator catches out-of-DLC signal and invalid scale" {
  let invalid = signal(start_bit=7, bit_length=2, factor=0.0)
  let message = @moondbc.MessageDefinition::{
    id: 2U,
    name: "M",
    dlc: 1,
    signals: [invalid],
    source_line: 1,
  }
  let issues = @moondbc.validate_schema(@moondbc.DbcDatabase::{
    messages: [message],
    value_descriptions: [],
    comments: [],
    diagnostics: [],
  })
  assert_true(has_issue(issues, "SIGNAL_OUT_OF_DLC"))
  assert_true(has_issue(issues, "INVALID_SCALE"))
}

///|
test "validator catches invalid physical range and unsupported identifier" {
  let invalid = signal(bit_length=8, minimum=Some(20.0), maximum=Some(10.0))
  let out_of_range_id = @moondbc.MessageDefinition::{
    id: 0x800U,
    name: "M",
    dlc: 1,
    signals: [invalid],
    source_line: 1,
  }
  let issues = @moondbc.validate_schema(@moondbc.DbcDatabase::{
    messages: [out_of_range_id],
    value_descriptions: [],
    comments: [],
    diagnostics: [],
  })
  assert_true(has_issue(issues, "INVALID_RANGE"))
  assert_true(has_issue(issues, "MESSAGE_ID_OUT_OF_RANGE"))
}

///|
fn has_issue(issues : Array[@moondbc.ValidationIssue], code : String) -> Bool {
  for issue in issues {
    if issue.code == code {
      return true
    }
  }
  false
}

///|
fn unsigned_max(width : Int) -> UInt64 {
  if width == 64 {
    0xFFFFFFFFFFFFFFFFUL
  } else {
    (1UL << width) - 1UL
  }
}

///|
fn signed_bounds(width : Int) -> (Int64, Int64) {
  if width == 64 {
    (-9223372036854775808L, 9223372036854775807L)
  } else {
    let magnitude = 1L << (width - 1)
    (-magnitude, magnitude - 1L)
  }
}

///|
test "database frame API encodes named values independent of input order" {
  let database = match
    @moondbc.parse_dbc(
      "BO_ 256 Pair: 2 ECU\n SG_ A : 0|8@1+ (1,0) [0|255] \"\" ECU\n SG_ B : 8|8@1+ (1,0) [0|255] \"\" ECU",
    ) {
    Ok(database) => database
    Err(_) => fail("valid pair DBC did not parse")
  }
  let payload = match
    @moondbc.encode_frame(database, "Pair", [
      ("B", @moondbc.UnsignedValue(0x22UL)),
      ("A", @moondbc.UnsignedValue(0x11UL)),
    ]) {
    Ok(payload) => payload
    Err(_) => fail("named frame encoding failed")
  }
  assert_eq(payload, Bytes::from_array([b'\x11', b'\x22']))
  match @moondbc.decode_frame(database, 256U, payload) {
    Ok(frame) => {
      assert_eq(frame.message_name, "Pair")
      assert_eq(frame.message_id, 256U)
      match frame.values[0].1 {
        @moondbc.UnsignedValue(raw) => assert_eq(raw, 0x11UL)
        _ => fail("first named signal was not unsigned")
      }
      match frame.values[1].1 {
        @moondbc.UnsignedValue(raw) => assert_eq(raw, 0x22UL)
        _ => fail("second named signal was not unsigned")
      }
    }
    Err(_) => fail("frame decoding failed")
  }
}

///|
test "database frame API reports missing duplicate and unknown signals" {
  let database = match
    @moondbc.parse_dbc(
      "BO_ 256 Pair: 2 ECU\n SG_ A : 0|8@1+ (1,0) [0|255] \"\" ECU\n SG_ B : 8|8@1+ (1,0) [0|255] \"\" ECU",
    ) {
    Ok(database) => database
    Err(_) => fail("valid pair DBC did not parse")
  }
  assert_true(
    @moondbc.encode_frame(database, "Pair", [("A", @moondbc.UnsignedValue(1UL))])
    is Err(@moondbc.MissingSignalValue("B")),
  )
  assert_true(
    @moondbc.encode_frame(database, "Pair", [
      ("A", @moondbc.UnsignedValue(1UL)),
      ("A", @moondbc.UnsignedValue(2UL)),
      ("B", @moondbc.UnsignedValue(3UL)),
    ])
    is Err(@moondbc.DuplicateSignalValue("A")),
  )
  assert_true(
    @moondbc.encode_frame(database, "Pair", [
      ("A", @moondbc.UnsignedValue(1UL)),
      ("B", @moondbc.UnsignedValue(2UL)),
      ("C", @moondbc.UnsignedValue(3UL)),
    ])
    is Err(@moondbc.UnknownSignalValue("C")),
  )
}

///|
test "database frame API reports unknown messages" {
  let database = match
    @moondbc.parse_dbc(
      "BO_ 256 One: 1 ECU\n SG_ A : 0|8@1+ (1,0) [0|255] \"\" ECU",
    ) {
    Ok(database) => database
    Err(_) => fail("valid DBC did not parse")
  }
  assert_true(
    @moondbc.decode_frame(database, 257U, Bytes::make(1, 0U.to_byte()))
    is Err(@moondbc.UnknownMessageId(257U)),
  )
  assert_true(
    @moondbc.encode_frame(database, "Missing", [
      ("A", @moondbc.UnsignedValue(0UL)),
    ])
    is Err(@moondbc.UnknownMessageName("Missing")),
  )
}
