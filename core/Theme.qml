pragma Singleton
import QtQuick
QtObject {
  property color background: "#141314"
  property color surface: "#141314"
  property color surfaceBright: "#3a3939"
  property color surfaceDim: "#141314"
  property color surfaceContainer: "#201f20"
  property color surfaceVariant: "#48464b"
  property color primary: "#cbc4d1"
  property color primaryFg: "#322f39"
  property color secondary: "#cac5ca"
  property color tertiary: "#cec6b2"
  property color backgroundFg: "#e6e1e2"
  property color surfaceFg: "#e6e1e2"
  property color surfaceVariantFg: "#cac5cb"
  property color outline: "#938f95"
  property color outlineVariant: "#48464b"
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
