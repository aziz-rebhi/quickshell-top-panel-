import QtQuick
import QtQuick.Layouts
import "../../core"

RowLayout {
  id: weatherWidget
  spacing: 8

  property real temperature: 0
  property int weatherCode: -1
  property string city: ""

  Text {
    text: weatherWidget.weatherCode < 0 ? "󰖙"
      : weatherWidget.weatherCode === 0 ? "󰖨"
      : weatherWidget.weatherCode <= 3 ? "󰖕"
      : weatherWidget.weatherCode <= 48 ? "󰖋"
      : weatherWidget.weatherCode <= 57 ? "󰖗"
      : weatherWidget.weatherCode <= 67 ? "󰖖"
      : weatherWidget.weatherCode <= 77 ? "󰖘"
      : weatherWidget.weatherCode <= 82 ? "󰖖"
      : weatherWidget.weatherCode >= 95 ? "󰖓"
      : "󰖙"
    color: Theme.primary
    font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
  }

  Text {
    text: weatherWidget.temperature.toFixed(0) + "°"
    color: Theme.text
    font { family: "Inter"; pixelSize: 13; weight: 700 }
  }

  Text {
    text: weatherWidget.city
    visible: city.length > 0
    color: Theme.subtext
    font { family: "Inter"; pixelSize: 10 }
    elide: Text.ElideRight
    Layout.maximumWidth: 100
  }
}
