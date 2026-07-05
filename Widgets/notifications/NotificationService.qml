import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Item {
  id: notifService

  property bool doNotDisturb: false

  property var latestNotification: null
  property var latestNotificationData: null
  property var storedNotifications: []

  NotificationServer {
    actionsSupported: true

    onNotification: (notification) => {
      var data = {
        appName: notification.appName,
        appIcon: notification.appIcon,
        summary: notification.summary,
        body: notification.body,
        urgency: notification.urgency,
        id: notification.id,
        actions: notification.actions,
        hasInlineReply: notification.hasInlineReply,
        inlineReplyPlaceholder: notification.inlineReplyPlaceholder,
        timestamp: Date.now()
      };

      var lock = null;
      try {
        lock = Qt.createQmlObject(
          'import Quickshell; RetainableLock { }',
          notifService, "notifLock"
        );
        lock.object = notification;
        lock.locked = true;
      } catch (e) {}

      data._lock = lock;

      if (!notifService.doNotDisturb) {
        notifService.latestNotification = notification;
        notifService.latestNotificationData = data;
      }

      var arr = notifService.storedNotifications.slice();
      arr.push(data);
      if (arr.length > 50) arr.splice(0, arr.length - 50);
      notifService.storedNotifications = arr;
    }
  }

  function dismissNotif(item) {
    if (!item) return;

    if (item.ref)
      item.ref.dismiss();
    else if (item.dismiss)
      item.dismiss();

    var itemId = item.id;
    if (itemId === undefined) return;

    var arr = storedNotifications.slice();
    var idx = -1;
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === itemId) { idx = i; break; }
    }
    if (idx >= 0) {
      var removed = arr[idx];
      if (removed._lock) {
        removed._lock.locked = false;
        removed._lock.destroy();
      }
      arr.splice(idx, 1);
    }
    storedNotifications = arr;

    if (latestNotificationData && latestNotificationData.id === itemId)
      latestNotificationData = null;
    if (latestNotification && latestNotification.id === itemId)
      latestNotification = null;
  }

  function dismissBanner(item) {
    // Only clears the active banner, keeps notification in history
    var itemId = item && item.id;
    if (itemId === undefined) return;

    if (latestNotificationData && latestNotificationData.id === itemId)
      latestNotificationData = null;
    if (latestNotification && latestNotification.id === itemId)
      latestNotification = null;

    // Release the lock so the notification can be freed by the server
    var arr = storedNotifications;
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].id === itemId && arr[i]._lock) {
        arr[i]._lock.locked = false;
        arr[i]._lock.destroy();
        arr[i]._lock = null;
        break;
      }
    }
  }

  function clearAll() {
    var arr = storedNotifications.slice();
    for (var i = 0; i < arr.length; i++) {
      var item = arr[i];
      if (item._lock) {
        item._lock.locked = false;
        item._lock.destroy();
      }
    }
    storedNotifications = [];
    latestNotificationData = null;
    latestNotification = null;
  }
}
