import QtQuick

// Component that renders either solid background, diagonal hatching, dots, or crosshatch
Item {
  id: root

  property color backgroundColor: "#1e1e1e"
  property color stripeColor: "#e68e0d"
  property string pattern: "solid" // "solid", "stripe-45", "stripe-135", "dots", "crosshatch"
  property real radius: 0
  property real stripeSpacing: 10
  property real stripeWidth: 2.5

  clip: true

  // Solid background fill
  Rectangle {
    id: bgRect
    anchors.fill: parent
    color: root.backgroundColor
    radius: root.radius
  }

  // Canvas for procedural patterns (stripes, dots, crosshatch)
  Canvas {
    id: patternCanvas
    anchors.fill: parent
    visible: root.pattern !== "solid"

    onPaint: {
      var ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);

      if (root.pattern === "solid") return;

      ctx.save();
      ctx.strokeStyle = root.stripeColor;
      ctx.fillStyle = root.stripeColor;
      ctx.lineWidth = root.stripeWidth;

      var step = root.stripeSpacing;

      if (root.pattern === "stripe-45") {
        // Forward diagonal lines (///)
        for (var x = -height; x < width; x += step) {
          ctx.beginPath();
          ctx.moveTo(x, 0);
          ctx.lineTo(x + height, height);
          ctx.stroke();
        }
      } else if (root.pattern === "stripe-135") {
        // Backward diagonal lines (\\\)
        for (var x = 0; x < width + height; x += step) {
          ctx.beginPath();
          ctx.moveTo(x, 0);
          ctx.lineTo(x - height, height);
          ctx.stroke();
        }
      } else if (root.pattern === "dots") {
        // Stippled dot grid
        var r = root.stripeWidth * 0.75;
        for (var px = step / 2; px < width; px += step) {
          for (var py = step / 2; py < height; py += step) {
            ctx.beginPath();
            ctx.arc(px, py, r, 0, 2 * Math.PI);
            ctx.fill();
          }
        }
      } else if (root.pattern === "crosshatch") {
        // Grid lines (horizontal + vertical)
        for (var gx = 0; gx < width; gx += step) {
          ctx.beginPath();
          ctx.moveTo(gx, 0);
          ctx.lineTo(gx, height);
          ctx.stroke();
        }
        for (var gy = 0; gy < height; gy += step) {
          ctx.beginPath();
          ctx.moveTo(0, gy);
          ctx.lineTo(width, gy);
          ctx.stroke();
        }
      }

      ctx.restore();
    }

    Connections {
      target: root
      function onPatternChanged() { patternCanvas.requestPaint(); }
      function onBackgroundColorChanged() { patternCanvas.requestPaint(); }
      function onStripeColorChanged() { patternCanvas.requestPaint(); }
      function onWidthChanged() { patternCanvas.requestPaint(); }
      function onHeightChanged() { patternCanvas.requestPaint(); }
    }
  }
}
