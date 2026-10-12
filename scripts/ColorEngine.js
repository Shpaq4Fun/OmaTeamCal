// scripts/ColorEngine.js
// Handles color interpolation between theme background and accent,
// and supplies styling parameters for cards and patterns.

.pragma library

// Parse a hex color string like "#rrggbb" into {r, g, b} normalized to [0..1]
function parseHex(h) {
  var s = String(h || "#000000").replace("#", "");
  if (s.length === 3) s = s[0]+s[0]+s[1]+s[1]+s[2]+s[2];
  return {
    r: parseInt(s.substring(0, 2), 16) / 255.0,
    g: parseInt(s.substring(2, 4), 16) / 255.0,
    b: parseInt(s.substring(4, 6), 16) / 255.0
  };
}

// Resolve either a Qt color object or hex string to {r, g, b}
function toRGB(c) {
  if (typeof c === "string") return parseHex(c);
  // Qt color object has .r, .g, .b already normalized
  if (c && typeof c.r === "number") return { r: c.r, g: c.g, b: c.b };
  return { r: 0, g: 0, b: 0 };
}

// Linear interpolation between two colors (hex string or Qt color), returns a Qt color
function lerpColor(c1, c2, t) {
  var a = toRGB(c1);
  var b = toRGB(c2);
  return Qt.rgba(
    a.r + (b.r - a.r) * t,
    a.g + (b.g - a.g) * t,
    a.b + (b.b - a.b) * t,
    1.0
  );
}

// 4 discrete tint steps: from dark/subtle wash to bright accent
var TINT_LEVELS = [0.18, 0.38, 0.62, 0.88];

// Pattern names supported by PatternRect.qml
var PATTERN_NAMES = [
  "solid",       // 0: smooth/flat
  "stripe-45",   // 1: forward diagonal hatching (///)
  "stripe-135",  // 2: backward diagonal hatching (\\\)
  "dots",        // 3: stippled / dotted grid
  "crosshatch"   // 4: grid / crosshatch
];

// Returns a style object for a given tint level (0..3) and pattern index (0..4)
function getStyleDefinition(tintIndex, patternIndex, themeAccent, themeBg) {
  var factor = TINT_LEVELS[Math.max(0, Math.min(TINT_LEVELS.length - 1, tintIndex))];
  var pattern = PATTERN_NAMES[Math.max(0, Math.min(PATTERN_NAMES.length - 1, patternIndex))];

  // Base background: interpolate from theme background towards theme accent
  var baseBg = lerpColor(themeBg, themeAccent, factor);

  // Pattern stripe color: a 20-30% shift to create subtle texture contrast
  var stripeColor = factor > 0.5
    ? lerpColor(baseBg, themeBg, 0.28)
    : lerpColor(baseBg, themeAccent, 0.40);

  // Text: dark for bright tints (high factor), light for dark tints
  var bgRGB = toRGB(baseBg);
  var luminance = 0.299 * bgRGB.r + 0.587 * bgRGB.g + 0.114 * bgRGB.b;
  var textColor = luminance > 0.45 ? Qt.rgba(0.05, 0.05, 0.05, 1.0) : Qt.rgba(0.94, 0.94, 0.94, 1.0);

  // Border: the accent color at a slightly brighter value
  var borderColor = lerpColor(themeAccent, Qt.rgba(1, 1, 1, 1.0), 0.15);

  return {
    tintFactor: factor,
    pattern: pattern,
    backgroundColor: baseBg,
    stripeColor: stripeColor,
    borderColor: borderColor,
    textColor: textColor
  };
}
