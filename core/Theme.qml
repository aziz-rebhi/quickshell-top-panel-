pragma Singleton
import QtQuick
QtObject {
  property color background: "#000000"
  property color surface: "#000000"
  property color surfaceBright: "#1a1a1a"
  property color surfaceDim: "#000000"
  property color surfaceContainer: "#0a0a0a"
  property color surfaceVariant: "#121212"
  property color primary: "#ffb4a9"
  property color primaryFg: "#690001"
  property color secondary: "#ffb4a9"
  property color tertiary: "#99cbff"
  property color backgroundFg: "#e8e8e8"
  property color surfaceFg: "#e8e8e8"
  property color surfaceVariantFg: "#9a9a9a"
  property color outline: "#5a5a5a"
  property color outlineVariant: "#1a1a1a"
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
