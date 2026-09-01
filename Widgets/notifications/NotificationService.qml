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
    imageSupported: true
    bodyImagesSupported: true

    onNotification: (notification) => {
      notification.tracked = true;
      var data = {
        appName: notification.appName,
        appIcon: notification.appIcon,
        summary: notification.summary,
        body: notification.body,
        urgency: notification.urgency,
        id: notification.id,
        ref: notification,
        actions: notification.actions,
        hasInlineReply: notification.hasInlineReply,
        inlineReplyPlaceholder: notification.inlineReplyPlaceholder,
        resident: notification.resident,
        image: notification.image,
        progress: notification.hints && notification.hints["value"] !== undefined
          ? (notification.hints["value"] * 100 / (notification.hints["value-max"] || 100)) : -1,
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

      var isCritical = notification.urgency === NotificationUrgency.Critical;
      if (!notifService.doNotDisturb || isCritical) {
        notifService.latestNotification = notification;
        notifService.latestNotificationData = data;
      }

      var arr = notifService.storedNotifications.slice();
      arr.push(data);
      // Trim oldest entries and release their RetainableLocks to avoid leaks
      while (arr.length > 50) {
        var old = arr.shift();
        if (old && old.ref) { try { old.ref.dismiss(); } catch (e) {} }
        if (old && old._lock) {
          try {
            old._lock.locked = false;
            old._lock.destroy();
          } catch (e) {}
        }
      }
      notifService.storedNotifications = arr;
    }
  }

  function dismissNotif(item) {
    if (!item) return;

    var itemId = item.id;
    var arr = storedNotifications.slice();
    var idx = -1;
    if (itemId !== undefined) {
      for (var i = 0; i < arr.length; i++) {
        if (arr[i].id === itemId) { idx = i; break; }
      }
    }
    if (idx < 0 && item.ref) {
      for (var j = 0; j < arr.length; j++) {
        if (arr[j].ref === item.ref) { idx = j; break; }
      }
    }

    // Dismiss the server-side notification BEFORE releasing its lock, so the
    // Notification object is still alive when we call dismiss() on it.
    try {
      if (item.ref)
        item.ref.dismiss();
      else if (item.dismiss)
        item.dismiss();
    } catch (e) {}

    if (idx >= 0) {
      var removed = arr[idx];
      if (removed._lock) {
        removed._lock.locked = false;
        removed._lock.destroy();
      }
      arr.splice(idx, 1);
    }
    storedNotifications = arr;

    if (itemId !== undefined) {
      if (latestNotificationData && latestNotificationData.id === itemId)
        latestNotificationData = null;
      if (latestNotification && latestNotification.id === itemId)
        latestNotification = null;
    } else if (item.ref) {
      if (latestNotification === item.ref) { latestNotification = null; }
      if (latestNotificationData && latestNotificationData.ref === item.ref)
        latestNotificationData = null;
    }
  }

  function dismissBanner(item) {
    // Only clears the active banner, keeps notification in history
    if (!item) return;
    var itemId = item.id;
    if (itemId === undefined) return;

    if (item.ref)
      item.ref.dismiss();
    else if (item.dismiss)
      item.dismiss();

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