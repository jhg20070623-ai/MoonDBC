///|
fn main raise {
  let source = "BO_ 256 Demo: 2 ECU\n SG_ Speed : 4|12@1+ (0.5,-1) [-1|2047] \"km/h\" ECU\n SG_ Mode : 0|2@1+ (1,0) [0|3] \"\" ECU"
  let database = match @dbc.parse_dbc(source) {
    Ok(database) => database
    Err(error) => fail("parse error on line \{error.line}: \{error.message}")
  }
  let decoded = match
    @dbc.decode_frame(database, 256U, Bytes::from_array([b'\xA0', b'\xBC'])) {
    Ok(frame) => frame
    Err(_) => fail("decode failed")
  }
  for (name, raw) in decoded.values {
    match raw {
      @dbc.UnsignedValue(value) => println("\{name}=\{value}")
      @dbc.SignedValue(value) => println("\{name}=\{value}")
    }
  }
}
