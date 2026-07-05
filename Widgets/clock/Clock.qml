import QtQuick

Item {
  width: mainWidget.width
  height: mainWidget.height

  signal toggleControlCenter()
  signal notifDismissed(var notifRef)
  signal notifBannerDismissed(var notifRef)

  property var latestNotification: null
  property var latestNotificationData: null
  property var storedNotifications: []
  property alias showPowerMenu: mainWidget.showPowerMenu
  property alias showAskpass: mainWidget.showAskpass
  property alias showAppLauncher: mainWidget.showAppLauncher
  property alias showWallpaperMenu: mainWidget.showWallpaperMenu
  property alias wallpaperSvc: mainWidget.wallpaperSvc
  property alias modeSvc: mainWidget.modeSvc
  property alias askpassSvc: mainWidget.askpassSvc

  function showModeIndicator() { mainWidget.showModeIndicator(); }

  ClockWidget {
    id: mainWidget
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter

    latestNotification: parent.latestNotification
    latestNotificationData: parent.latestNotificationData
    storedNotifications: parent.storedNotifications

    onToggleControlCenter: parent.toggleControlCenter()
    onNotifDismissed: (notifRef) => parent.notifDismissed(notifRef)
    onNotifBannerDismissed: (notifRef) => parent.notifBannerDismissed(notifRef)
  }
}
