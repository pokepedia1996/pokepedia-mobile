import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours, curves and type of the onboarding designs, at the design's own
/// pixel values: `pokepad.pen` "Onboarding Baru 0–9" and the motion
/// prototype `animasi-onboarding/index.html`. Nothing here is scaled; the
/// shared setup kit's 0.9 factor belongs to the other flows.
const onbInk = Color(0xFF1C1413);
const onbRed = Color(0xFFAC403A);
const onbMuted = Color(0xFF6B6564);
const onbLine = Color(0xFFE0D8C8);
const onbOff = Color(0xFFD9CDB8);
const onbGreen = Color(0xFF2E9E57);
const onbDisabled = Color(0xFFCBC1AF);

/// The prototype's curves: `OUT`, `IN`, the page `push`, and the dot spring.
const onbOut = Cubic(.2, .8, .2, 1);
const onbIn = Cubic(.5, 0, .75, 0);
const onbPush = Cubic(.22, .8, .2, 1);
const onbSpring = Cubic(.3, 1.4, .5, 1);
const onbPop = Cubic(.3, 1.5, .5, 1);

/// Urbanist, the body face.
TextStyle onbBody(
  double size,
  Color color, [
  FontWeight weight = FontWeight.w400,
  double? height,
]) => GoogleFonts.urbanist(
  fontSize: size,
  fontWeight: weight,
  color: color,
  // The design's boxes are about 1.2 of the size for Urbanist (16 → 19,
  // 15 → 18, 14 → 17); stated, so a stand-in font cannot change them.
  height: height ?? 1.2,
);

/// Cal Sans, the headline face.
TextStyle onbHeading(double size, Color color, {double? height}) => TextStyle(
  fontFamily: 'CalSans',
  fontSize: size,
  color: color,
  // 31 → 40, 20 → 26 in the design.
  height: height ?? 1.3,
);

/// Patrick Hand, for the handwritten lines: 18 → 24, 17 → 23, 16 → 22 in
/// the design, so about 1.35.
TextStyle onbHand(double size, Color color) => TextStyle(
  fontFamily: 'PatrickHand',
  fontSize: size,
  color: color,
  height: 1.35,
);

/// How far along a track [ms] is, for something that starts at [delay], runs
/// [duration] and eases with [curve]: 0 before it starts, 1 once it is done.
double onbTrack(double ms, double delay, double duration, Curve curve) =>
    curve.transform(((ms - delay) / duration).clamp(0.0, 1.0));
