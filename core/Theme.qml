pragma Singleton
import QtQuick
QtObject {
  property color background: "#141316"
  property color surface: "#141316"
  property color surfaceBright: "#3b383c"
  property color surfaceDim: "#141316"
  property color surfaceContainer: "#211f23"
  property color surfaceVariant: "#49454e"
  property color primary: "#d3bcf8"
  property color primaryFg: "#392757"
  property color secondary: "#cec2dc"
  property color tertiary: "#eabe9e"
  property color backgroundFg: "#e6e1e6"
  property color surfaceFg: "#e6e1e6"
  property color surfaceVariantFg: "#cbc4cf"
  property color outline: "#958e99"
  property color outlineVariant: "#49454e"
  property color error: "#ffb4ab"
  property color accent: primary
  property color surfaceLight: surfaceVariant
  property color surfaceHover: surfaceBright
  property color container: surfaceContainer
  property color text: backgroundFg
  property color muted: outline
  property color subtext: surfaceVariantFg
  property color border: outlineVariant
  property color warning: tertiary
  property color success: primary
  property color danger: error
  property color overlay: "#00000099"
}
