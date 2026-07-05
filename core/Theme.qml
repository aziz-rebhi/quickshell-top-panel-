pragma Singleton
import QtQuick
QtObject {
  property color background: "#131314"
  property color surface: "#131314"
  property color surfaceBright: "#39393a"
  property color surfaceDim: "#131314"
  property color surfaceContainer: "#201f20"
  property color surfaceVariant: "#45474b"
  property color primary: "#c0c7d5"
  property color primaryFg: "#2a313c"
  property color secondary: "#c5c6cc"
  property color tertiary: "#d7c4ab"
  property color backgroundFg: "#e5e2e2"
  property color surfaceFg: "#e5e2e2"
  property color surfaceVariantFg: "#c5c6cc"
  property color outline: "#8f9096"
  property color outlineVariant: "#45474b"
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
