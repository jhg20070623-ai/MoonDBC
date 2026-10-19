# MoonDBC examples

These synthetic examples use only project-authored DBC data. Run from the
repository root:

```sh
moon run examples/api_demo
moon run cmd/moondbc -- validate testdata/minimal.dbc
moon run cmd/moondbc -- inspect testdata/common_header.dbc
moon run cmd/moondbc -- decode testdata/minimal.dbc --frame-id 256 --data A0BC
moon run cmd/moondbc -- encode testdata/minimal.dbc --message Minimal --signal IntelValue=3018 --signal Mode=2
```

The `A0 BC` example decodes `IntelValue` as raw `3018` and physical `1508` using
the fixture's factor `0.5` and offset `-1`. Encoding raw `3018` and `Mode=2`
produces `A2 BC`. This is a signal-level DBC codec example; it does not read CAN
hardware or capture bus traffic.
