// scripts/StyleAssigner.js
// Dynamically assigns distinct (tint, pattern) combinations to currently active members
// to maximize visual contrast among the active selection.

.pragma library
.import "ColorEngine.js" as ColorEngine

// Matrix of (tintIndex, patternIndex) prioritized to maximize distance
// Tints: 0 (subtle), 1 (muted), 2 (medium), 3 (bright)
// Patterns: 0 (solid), 1 (stripe-45), 2 (stripe-135), 3 (dots), 4 (crosshatch)
var PRIORITY_SLOTS = [
  // 1st pair: maximum contrast (bright solid vs dark diagonal)
  { tint: 3, pattern: 0 },
  { tint: 0, pattern: 1 },
  // 3rd member: medium reverse-diagonal
  { tint: 2, pattern: 2 },
  // 4th member: muted dotted
  { tint: 1, pattern: 3 },
  // 5th member: bright crosshatch
  { tint: 3, pattern: 4 },
  // 6th member: dark solid
  { tint: 0, pattern: 0 },
  // 7th member: medium forward-diagonal
  { tint: 2, pattern: 1 },
  // 8th member: muted reverse-diagonal
  { tint: 1, pattern: 2 },
  // 9th member: bright dots
  { tint: 3, pattern: 3 },
  // 10th member: dark crosshatch
  { tint: 0, pattern: 4 },
  // 11th member: medium solid
  { tint: 2, pattern: 0 },
  // 12th member: muted solid
  { tint: 1, pattern: 0 },
  // Remaining slots for up to 20 combinations
  { tint: 0, pattern: 2 },
  { tint: 0, pattern: 3 },
  { tint: 1, pattern: 1 },
  { tint: 1, pattern: 4 },
  { tint: 2, pattern: 3 },
  { tint: 2, pattern: 4 },
  { tint: 3, pattern: 1 },
  { tint: 3, pattern: 2 }
];

function assignStyles(activeMembers, themeAccent, themeBg) {
  var map = {};
  if (!activeMembers || activeMembers.length === 0) return map;

  for (var i = 0; i < activeMembers.length; i++) {
    var member = activeMembers[i];
    var slot = PRIORITY_SLOTS[i % PRIORITY_SLOTS.length];
    var style = ColorEngine.getStyleDefinition(slot.tint, slot.pattern, themeAccent, themeBg);
    map[member.id] = style;
  }

  return map;
}
