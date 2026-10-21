///|
fn main {
  let intel = @moondbc.SignalDefinition::{
    name: "IntelValue",
    start_bit: 4,
    bit_length: 12,
    byte_order: @moondbc.Intel,
    signedness: @moondbc.Unsigned,
    factor: 0.5,
    offset: -1.0,
    minimum: Some(-1.0),
    maximum: Some(2047.0),
    unit: "km/h",
    multiplexing: @moondbc.NotMultiplexed,
    source_line: 1,
  }
  let motorola = @moondbc.SignalDefinition::{
    name: "MotorolaValue",
    start_bit: 7,
    bit_length: 12,
    byte_order: @moondbc.Motorola,
    signedness: @moondbc.Unsigned,
    factor: 1.0,
    offset: 0.0,
    minimum: Some(0.0),
    maximum: Some(4095.0),
    unit: "raw",
    multiplexing: @moondbc.NotMultiplexed,
    source_line: 1,
  }
  let signed = @moondbc.SignalDefinition::{
    name: "SignedValue",
    start_bit: 0,
    bit_length: 12,
    byte_order: @moondbc.Intel,
    signedness: @moondbc.Signed,
    factor: 1.0,
    offset: 0.0,
    minimum: Some(-2048.0),
    maximum: Some(2047.0),
    unit: "raw",
    multiplexing: @moondbc.NotMultiplexed,
    source_line: 1,
  }
  let intel_payload = Bytes::from_array([b'\xA0', b'\xBC'])
  let motorola_payload = Bytes::from_array([b'\xAB', b'\xC0'])
  let signed_low = Bytes::from_array([b'\x00', b'\x08'])
  let signed_high = Bytes::from_array([b'\xFF', b'\x07'])
  print_raw("intel_raw", intel, intel_payload)
  print_physical("intel_physical", intel, intel_payload)
  print_encoded(
    "intel_encoded",
    intel,
    @moondbc.UnsignedValue(0xBCAUL),
    intel_payload,
  )
  print_raw("motorola_raw", motorola, motorola_payload)
  print_encoded(
    "motorola_encoded",
    motorola,
    @moondbc.UnsignedValue(0xABCUL),
    motorola_payload,
  )
  print_raw("signed_min", signed, signed_low)
  print_raw("signed_max", signed, signed_high)
  let widths = [1, 7, 8, 9, 12, 16, 32, 63, 64]
  for width in widths {
    let unsigned_signal = make_motorola_signal(width, @moondbc.Unsigned)
    let unsigned_value = unsigned_max(width)
    print_motorola_vector(
      "motorola_u",
      width,
      unsigned_signal,
      @moondbc.UnsignedValue(unsigned_value),
    )
    let (minimum, maximum) = signed_bounds(width)
    let signed_signal = make_motorola_signal(width, @moondbc.Signed)
    print_motorola_vector(
      "motorola_smin",
      width,
      signed_signal,
      @moondbc.SignedValue(minimum),
    )
    print_motorola_vector(
      "motorola_smax",
      width,
      signed_signal,
      @moondbc.SignedValue(maximum),
    )
  }
}

///|
fn print_raw(
  key : String,
  signal : @moondbc.SignalDefinition,
  payload : Bytes,
) -> Unit {
  match @moondbc.decode_raw_signal(signal, payload) {
    Ok(@moondbc.UnsignedValue(value)) => println("\{key}=\{value}")
    Ok(@moondbc.SignedValue(value)) => println("\{key}=\{value}")
    Err(_) => println("\{key}=ERROR")
  }
}

///|
fn print_physical(
  key : String,
  signal : @moondbc.SignalDefinition,
  payload : Bytes,
) -> Unit {
  match @moondbc.decode_raw_signal(signal, payload) {
    Ok(raw) =>
      match @moondbc.decode_physical(signal, raw) {
        Ok(value) => println("\{key}=\{value}")
        Err(_) => println("\{key}=ERROR")
      }
    Err(_) => println("\{key}=ERROR")
  }
}

///|
fn print_encoded(
  key : String,
  signal : @moondbc.SignalDefinition,
  raw : @moondbc.RawSignalValue,
  payload : Bytes,
) -> Unit {
  match
    @moondbc.encode_raw_signal(
      signal,
      raw,
      Bytes::make(payload.length(), 0U.to_byte()),
    ) {
    Ok(encoded) => {
      let mut hex = ""
      for byte in encoded {
        hex = hex + byte.to_hex()
      }
      println("\{key}=\{hex}")
    }
    Err(_) => println("\{key}=ERROR")
  }
}

///|
fn make_motorola_signal(
  width : Int,
  signedness : @moondbc.Signedness,
) -> @moondbc.SignalDefinition {
  @moondbc.SignalDefinition::{
    name: "Value",
    start_bit: 7,
    bit_length: width,
    byte_order: @moondbc.Motorola,
    signedness,
    factor: 1.0,
    offset: 0.0,
    minimum: None,
    maximum: None,
    unit: "",
    multiplexing: @moondbc.NotMultiplexed,
    source_line: 1,
  }
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
fn print_motorola_vector(
  prefix : String,
  width : Int,
  signal : @moondbc.SignalDefinition,
  raw : @moondbc.RawSignalValue,
) -> Unit {
  let key = "\{prefix}_\{width}"
  match @moondbc.encode_raw_signal(signal, raw, Bytes::make(8, 0U.to_byte())) {
    Err(_) => println("\{key}_error=encode")
    Ok(payload) => {
      let mut hex = ""
      for byte in payload {
        hex = hex + byte.to_hex()
      }
      println("\{key}_hex=\{hex}")
      match @moondbc.decode_raw_signal(signal, payload) {
        Ok(@moondbc.UnsignedValue(value)) => println("\{key}_raw=\{value}")
        Ok(@moondbc.SignedValue(value)) => println("\{key}_raw=\{value}")
        Err(_) => println("\{key}_error=decode")
      }
    }
  }
}
