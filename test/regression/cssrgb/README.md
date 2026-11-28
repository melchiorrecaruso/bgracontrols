# CSS RGB parser regression

Checks `BCColors.TryParseCSSRGB`:

- strict absolute `rgb()`/`rgba()` in space and comma syntax: channels, percentages,
  exponents, clamping and BGRABitmap `HalfUp` rounding (ties up), including
  inputs with more than nine fractional digits;
- relative `rgb(from <origin> r g b [/ alpha])`: the origin is returned as
  text, not resolved; alpha is kept or overridden;
- valid origins: hex, named and system colors, nested functions up to 32
  levels;
- rejection of invalid syntax, of historical forms (`rgb 1,2,3`, `rgb (1,2,3)`,
  trailing text, Pascal numbers, mixed comma channels) and of unknown or
  unsupported origins, including LCL `cl...` names even in nested functions;
- `TryParseCSSPercentage`: required `%`, clamping and rounding.

FPCUnit program built with the `nogui` widgetset; `.github/workflows/make.pas`
builds and runs it. By hand:

```sh
lazbuild --build-all test_cssrgb.lpi
./test_cssrgb --all --format=plain
```
