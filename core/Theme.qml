pragma Singleton
import QtQuick
QtObject {
  property color background: "#121412"
  property color surface: "#121412"
  property color surfaceBright: "#383a37"
  property color surfaceDim: "#121412"
  property color surfaceContainer: "#1e201e"
  property color surfaceVariant: "#414843"
  property color primary: "#a7d0b3"
  property color primaryFg: "#113723"
  property color secondary: "#bacbbd"
  property color tertiary: "#f5b7bb"
  property color backgroundFg: "#e2e3df"
  property color surfaceFg: "#e2e3df"
  property color surfaceVariantFg: "#c1c8c1"
  property color outline: "#8b938c"
  property color outlineVariant: "#414843"
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
