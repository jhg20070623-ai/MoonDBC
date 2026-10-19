# Codec precision policy

## Raw values

Raw codec operations preserve integers exactly using `UInt64` for unsigned
signals and `Int64` for signed signals. Signal widths from 1 through 64 bits
are supported subject to fitting within the message DLC. Encoding rejects a
signedness mismatch or a value outside the width instead of truncating it.

## Physical values

Physical decode applies `raw * factor + offset` using `Double`. To prevent a
lossy raw-to-physical conversion from being presented as exact, decode refuses
raw integer magnitudes above 2^53 (signed values also use the symmetric bound).
The raw value remains available even when physical conversion reports
`PhysicalPrecisionExceeded`.

Physical encoding reverses the scale and requires a finite result that maps to
an exact integer raw value. It rejects non-integral inverse scale, precision
overflow, invalid scale, and values outside declared minimum/maximum. It does
not round or clamp.

Declared physical bounds are enforced in both physical encode and physical
decode. A raw frame can still be decoded exactly even when physical conversion
fails because the decoded physical value lies outside the declared range.
