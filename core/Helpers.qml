pragma Singleton
import QtQuick

QtObject {
  function volumeIcon(vol, muted) {
    if (muted || vol <= 0) return "󰝟";
    if (vol < 0.34) return "󰕿";
    if (vol < 0.67) return "󰖀";
    return "󰕾";
  }

  function brightnessIcon(val) {
    if (val < 0.34) return "󰃞";
    if (val < 0.67) return "󰃟";
    return "󰃠";
  }

  function relTime(ts) {
    if (!ts) return "";
    var diff = Date.now() - ts;
    if (diff < 60000) return "now";
    if (diff < 3600000) return Math.floor(diff / 60000) + "m ago";
    if (diff < 86400000) return Math.floor(diff / 3600000) + "h ago";
    var days = Math.floor(diff / 86400000);
    return days === 1 ? "Yesterday" : days + "d ago";
  }

  function formatTime(sec) {
    if (!(sec > 0)) return "0:00";
    var total = Math.floor(sec);
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var ss = s < 10 ? "0" + s : "" + s;
    if (h > 0) {
      var mm = m < 10 ? "0" + m : "" + m;
      return h + ":" + mm + ":" + ss;
    }
    return m + ":" + ss;
  }

  function youtubeThumb(url) {
    if (!url) return "";
    var match = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
    return match ? "https://img.youtube.com/vi/" + match[1] + "/hqdefault.jpg" : "";
  }
}
