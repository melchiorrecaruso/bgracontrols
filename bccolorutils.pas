// SPDX-License-Identifier: LGPL-3.0-linking-exception
{ Text and CSS forms of BGRAControls colors, and color swatches. }
unit BCColorUtils;

{$IFDEF FPC}
{$mode objfpc}{$H+}
{$ENDIF}

interface

uses
  Classes, SysUtils, Graphics, Types, BGRABitmap, BGRABitmapTypes, BCColors;

type
  { Distinct types, so their editors do not apply to all strings. }
  TBCColorString = type string;      // '#RRGGBBAA'
  TBCCSSColorString = type string;   // see TryCSSColor

{ BGRAControls text, not CSS: an LCL identifier ('clBtnFace', 'clRed',
  'clDefault', 'clNone'), or '#RRGGBB[AA]' for an RGB without one.
  An alpha below 255 follows a name as a percentage: 'clBtnFace 50%',
  'clRed 49.8%' (whole when exact, otherwise one decimal). }
function BCToStr(const V: TBCColorValue): string;
{ Alpha as an opacity percentage: whole when it round-trips, otherwise one
  decimal digit. Shared by color serialization and picker display. }
function BCAlphaToStr(A: byte): string;
{ Valid CSS, preferring names: 'ThreeDFace', 'LinkText', 'red',
  'rgb(from ThreeDFace r g b / 50%)', '#RRGGBB[AA]', 'transparent'.
  System colors without a CSS name become their RGB now. scDefault is
  'revert' when opaque (a CSS-wide keyword: valid only as a whole property
  value), otherwise ADefault with its alpha.
  AResolved: always '#hex' or 'transparent'. }
function BCToCSS(const V: TBCColorValue; ADefault: TColor = clBlack;
  AResolved: boolean = False): string;
{ Reads BCToStr and CSS: clXxx identifiers, CSS named RGB colors, supported
  CSS system names/synonyms, '#hex', strict rgb()/rgba() and a name followed
  by a percentage ('clBtnFace 50%', 'red 20%'; '%' required, not after
  '#hex' or transparent), and 'revert' as clDefault (alone, as in CSS).
  Additional modern CSS roles (Canvas, Field...)
  are not mapped to LCL fallbacks. RGB functions use
  BCColors.TryParseCSSRGB, which accepts only CSS origins (not clXxx
  identifiers); they are converted recursively here into values, keeping
  symbolic identity.
  Outputs must not be used on failure. }
function TryStrToBC(const S: string; out V: TBCColorValue): boolean;

{ '#RRGGBB' or '#RRGGBBAA', '#' optional. }
function TryBCColor(const S: string; out P: TBGRAPixel): boolean;
function BCColorToString(const P: TBGRAPixel): string;
procedure DrawBCCheckers(Bmp: TBGRABitmap; const R: TRect);
procedure DrawColor(Canvas: TCanvas; const R: TRect; const P: TBGRAPixel); overload;
{ scDefault with ADefault = clDefault (unknown) is drawn as a hatch. }
procedure DrawColor(Canvas: TCanvas; const R: TRect; const V: TBCColorValue;
  ADefault: TColor = clDefault); overload;

{ CSS text as read by StrToBGRA. FormatCSSColor keeps the style of AStyle. }
function TryCSSColor(const S: string; out P: TBGRAPixel): boolean;
function FormatCSSColor(const P: TBGRAPixel; const AStyle: string): string;

implementation

uses
  LCLType;

{ Strict hex syntax for symbolic color text: '#' is required and partial
  channels ('?'), accepted by TryStrToBGRA, are not allowed. Like BGRABitmap,
  preserve RGB channels even when alpha is zero. }
function TryHexColor(const S: string; out P: TBGRAPixel): boolean;
var
  I, N: integer;
  Missing, Error: boolean;
begin
  Result := False;
  N := Length(S) - 1;
  if (S = '') or (S[1] <> '#') or not (N in [3, 4, 6, 8]) then Exit;
  for I := 2 to Length(S) do
    if not (S[I] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;
  P := BGRABlack;
  TryStrToBGRA(S, P, Missing, Error);
  Result := not (Missing or Error);
end;

{ The CSSColors table stores the 'gray' spelling; accept 'grey' aliases too. }
function TryCSSNamedColor(const AName: string; out P: TBGRAPixel): boolean;
var
  I: integer;
begin
  I := CSSColors.IndexOf(StringReplace(AName, 'grey', 'gray', [rfIgnoreCase]));
  Result := I >= 0;
  if Result then
    P := CSSColors[I];
end;

{ Opacity as a percentage: whole when it reads back to the same alpha byte,
  otherwise with one decimal, which is always enough (0.1% is 0.255 of a
  byte). Uses HalfUp, checked with the same parser as TryStrToBC. }
function BCAlphaToStr(A: byte): string;
var
  Tenths: integer;
  Parsed: byte;
begin
  Result := IntToStr(HalfUp(A * 100 / 255)) + '%';
  if TryParseCSSPercentage(Result, Parsed) and (Parsed = A) then Exit;
  Tenths := HalfUp(A * 1000 / 255);
  Result := IntToStr(Tenths div 10) + '.' + IntToStr(Tenths mod 10) + '%';
end;

{ BCColors parses RGB syntax and validates the origin. Interpret that origin
  as a value here, preserving a system name rather than resolving its RGB. }
function TryRGBFunction(const S: string; out V: TBCColorValue): boolean;
var
  Base: string;
  P: TBGRAPixel;
  OverrideAlpha: boolean;
begin
  Result := TryParseCSSRGB(S, Base, P, OverrideAlpha);
  if not Result then Exit;
  if Base = '' then
  begin
    V := TBCColorValue.New(P);
    Exit;
  end;
  Result := TryStrToBC(Base, V);
  if Result and OverrideAlpha then
    V := V.WithAlpha(P.alpha);
end;

{ 'clBtnFace' or 'clBtnFace 50%' }
function ShortNameWithAlpha(const AName: string; AAlpha: byte): string;
begin
  if AAlpha = 255 then
    Result := AName
  else
    Result := AName + ' ' + BCAlphaToStr(AAlpha);
end;

{ 'ThreeDFace' or 'rgb(from ThreeDFace r g b / 50%)' }
function CSSNameWithAlpha(const AName: string; AAlpha: byte): string;
begin
  if AAlpha = 255 then
    Result := AName
  else
    Result := 'rgb(from ' + AName + ' r g b / ' + BCAlphaToStr(AAlpha) + ')';
end;

{ The CSS name of the RGB, whatever the alpha: 'red' or
  'rgb(from red r g b / 50%)'. '#RRGGBB[AA]' when the RGB has no name. }
function RGBToCSS(const P: TBGRAPixel): string;
var
  Opaque: TBGRAPixel;
begin
  Opaque := P;
  Opaque.alpha := 255;
  Result := BGRAToStr(Opaque, CSSColors, 0, True, True);
  if (Result = '') or (Result[1] = '#') then
    Exit(BGRAToStr(P, nil, 0, True, True));
  { Keep canonical names lowercase, but preserve uppercase hex digits. }
  Result := CSSNameWithAlpha(LowerCase(Result), P.alpha);
end;

function BCToStr(const V: TBCColorValue): string;
var
  Name: string;
  C: TColor;
  P: TBGRAPixel;
begin
  if V.Kind = scCustomRGB then
  begin
    P := V.ToBGRA;
    { 'clRed', 'clMoneyGreen'... the RGB of a fixed LCL color }
    if ColorToIdent(RGBToColor(P.red, P.green, P.blue), Name) then
      Exit(ShortNameWithAlpha(Name, P.alpha));
    Exit(BGRAToStr(P, nil, 0, True, True));
  end;
  if not V.Kind.TryToColor(C) then
    C := clDefault; // not reached: every named kind is an LCL color
  if V.Kind = scNone then
    Exit(ColorToString(C));
  Result := ShortNameWithAlpha(ColorToString(C), V.Alpha);
end;

function BCToCSS(const V: TBCColorValue; ADefault: TColor;
  AResolved: boolean): string;
var
  P: TBGRAPixel;
begin
  if ADefault = clDefault then
    ADefault := clBlack;
  if AResolved then
  begin
    P := V.ToBGRA(ADefault);
    if P.alpha = 0 then
      Exit('transparent');
    Exit(BGRAToStr(P, nil, 0, True, True));
  end;
  case V.Kind of
    scNone:
      Exit('transparent');
    scDefault:
      { 'revert' takes no alpha: use the default color instead. }
      if V.Alpha = 255 then
        Exit('revert')
      else
        Exit(BCToCSS(TBCColorValue.New(ADefault, V.Alpha), clBlack));
    scCustomRGB:
      Exit(RGBToCSS(V.ToBGRA));
  end;
  if V.Kind.CSSName <> '' then
    Exit(CSSNameWithAlpha(V.Kind.CSSName, V.Alpha));
  { system color without a CSS name: its RGB now }
  P := V.ToBGRA(ADefault);
  if P.alpha = 0 then
    Exit('transparent');
  Result := RGBToCSS(P);
end;

{ A single name: CSS system names, clXxx identifiers and CSS named colors. }
function TryNameToBC(const T: string; out V: TBCColorValue): boolean;
var
  P: TBGRAPixel;
  C: longint;
  K: TBCSymbolicColor;
begin
  Result := True;
  if TryCSSNameToSymbolic(T, K) then
    V := TBCColorValue.New(K)
  else if IdentToColor(T, C) then
    V := TBCColorValue.New(TColor(C))
  else if TryCSSNamedColor(T, P) then
    V := TBCColorValue.New(P)
  else
    Result := False;
end;

{ '<name> <percentage>': 'clBtnFace 50%', 'red 20%'. }
function TryShortForm(const T: string; out V: TBCColorValue): boolean;
var
  I: integer;
  A: byte;
begin
  Result := False;
  I := LastDelimiter(' '#9#10#12#13, T);
  if I <= 1 then Exit;
  if not TryParseCSSPercentage(Copy(T, I + 1, Length(T)), A) then Exit;
  if not TryNameToBC(TrimRight(Copy(T, 1, I - 1)), V) then Exit;
  { transparent has no opacity to set }
  if V.Kind = scNone then Exit;
  V := V.WithAlpha(A);
  Result := True;
end;

function TryStrToBC(const S: string; out V: TBCColorValue): boolean;
var
  T: string;
  P: TBGRAPixel;
begin
  T := Trim(S);
  Result := T <> '';
  if not Result then Exit;

  if TryNameToBC(T, V) then Exit;
  { BCToCSS output for clDefault: a whole value only, as in CSS }
  if SameText(T, 'revert') then
  begin
    V := TBCColorValue.New(scDefault);
    Exit;
  end;
  if Pos('(', T) > 0 then Exit(TryRGBFunction(T, V));
  if T[Length(T)] = '%' then Exit(TryShortForm(T, V));

  { '#' required: 'Face' is not #FFAACCEE }
  Result := TryHexColor(T, P);
  if Result then
    V := TBCColorValue.New(P);
end;

function TryBCColor(const S: string; out P: TBGRAPixel): boolean;
var
  T: string;
  I: integer;
begin
  P := BGRABlack;
  Result := False;
  T := Trim(S);
  if (T <> '') and (T[1] = '#') then
    Delete(T, 1, 1);
  if not (Length(T) in [6, 8]) then Exit;

  for I := 1 to Length(T) do
    if not (T[I] in ['0'..'9', 'a'..'f', 'A'..'F']) then Exit;

  Result := TryCSSColor('#' + T, P);
end;

function BCColorToString(const P: TBGRAPixel): string;
begin
  Result := BGRAToStr(P, nil, 0, False, True);
end;

procedure DrawBCCheckers(Bmp: TBGRABitmap; const R: TRect);
begin
  { White first: DrawCheckers starts with its "odd" color. }
  Bmp.DrawCheckers(R, BGRA(192, 192, 192), BGRAWhite, 6, 6);
end;

procedure DrawColor(Canvas: TCanvas; const R: TRect; const P: TBGRAPixel);
var
  Bmp: TBGRABitmap;
  Old: TColor;
begin
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;

  if P.alpha = 255 then
  begin
    Old := Canvas.Brush.Color;
    Canvas.Brush.Color := BGRAToColor(P);
    Canvas.FillRect(R);
    Canvas.Brush.Color := Old;
    Exit;
  end;

  Bmp := TBGRABitmap.Create(R.Right - R.Left, R.Bottom - R.Top);
  try
    DrawBCCheckers(Bmp, Rect(0, 0, Bmp.Width, Bmp.Height));
    Bmp.FillRect(0, 0, Bmp.Width, Bmp.Height, P, dmLinearBlend);
    Bmp.Draw(Canvas, R.Left, R.Top, True);
  finally
    Bmp.Free;
  end;
end;

procedure DrawColor(Canvas: TCanvas; const R: TRect; const V: TBCColorValue;
  ADefault: TColor);
var
  Bmp: TBGRABitmap;
  X: integer;
begin
  if (V.Kind <> scDefault) or (ADefault <> clDefault) then
  begin
    DrawColor(Canvas, R, V.ToBGRA(ADefault));
    Exit;
  end;
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;

  Bmp :=TBGRABitmap.Create(R.Right - R.Left, R.Bottom - R.Top, BGRAWhite);
  try
    X := -Bmp.Height;
    while X < Bmp.Width do
    begin
      Bmp.DrawLine(X, Bmp.Height, X + Bmp.Height, 0, BGRA(160, 160, 160), True);
      Inc(X, 4);
    end;
    Bmp.Draw(Canvas, R.Left, R.Top, True);
  finally
    Bmp.Free;
  end;
end;

function TryCSSColor(const S: string; out P: TBGRAPixel): boolean;
var
  Missing, Error: boolean;
begin
  P := BGRABlack;
  Result := False;
  if Trim(S) = '' then Exit;

  TryStrToBGRA(Trim(S), P, Missing, Error);
  Result := not (Missing or Error);
end;

function FormatCSSColor(const P: TBGRAPixel; const AStyle: string): string;
var
  T: string;
  FS: TFormatSettings;
begin
  T := LowerCase(Trim(AStyle));
  if Copy(T, 1, 3) = 'rgb' then
  begin
    if P.alpha = 255 then
      Exit(Format('rgb(%d,%d,%d)', [P.red, P.green, P.blue]));

    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    Exit(Format('rgba(%d,%d,%d,%s)', [P.red, P.green, P.blue,
      FloatToStrF(P.alpha / 255, ffGeneral, 3, 0, FS)]));
  end;
  if (Length(T) = 7) and (T[1] = '#') and (P.alpha = 255) then
    Exit(BGRAToStr(P, nil, 0, True, True));
  Result := BCColorToString(P);
end;

end.
