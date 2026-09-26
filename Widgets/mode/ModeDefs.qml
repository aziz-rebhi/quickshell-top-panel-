pragma Singleton
import QtQuick

/*
 * Mode definitions — pure UI data, separate from runtime state.
 * One row per mode: identity, messaging, conceptual policies and a
 * 0..100 efficiency→performance position for the profile indicator.
 * The controller (performance-mode) owns the real lever mapping; these
 * fields describe intent so the panel can render a mode without asking
 * the controller for presentation details.
 */

QtObject {
  readonly property var data: [
    {
      key: "silent",
      icon: "󰤆",
      name: "Silent",
      tag: "Low power",
      subtitle: "Cool & quiet everyday operation.",
      chips: ["AMD iGPU preferred", "quiet fan"],
      profile: 0,
      config: [
        ["CPU Policy", "Efficiency (powersave)"],
        ["GPU Policy", "AMD iGPU"],
        ["CPU Boost", "Off"],
        ["Cooling", "Quiet / automatic"],
        ["Background", "Efficiency-oriented"],
        ["Memory Policy", "Normal"]
      ]
    },
    {
      key: "balanced",
      icon: "󰒓",
      name: "Balanced",
      tag: "Daily use",
      subtitle: "Adaptive performance for default everyday use.",
      chips: ["hybrid GPU", "auto fan"],
      profile: 30,
      config: [
        ["CPU Policy", "Adaptive (schedutil)"],
        ["GPU Policy", "Hybrid"],
        ["CPU Boost", "Auto"],
        ["Cooling", "Automatic"],
        ["Background", "Normal"],
        ["Memory Policy", "Normal"]
      ]
    },
    {
      key: "performance",
      icon: "󰓅",
      name: "Performance",
      tag: "Heavy workloads",
      subtitle: "Sustained performance for heavy workstation workloads.",
      chips: ["NVIDIA on demand", "max CPU"],
      profile: 58,
      config: [
        ["CPU Policy", "Performance"],
        ["GPU Policy", "NVIDIA on demand"],
        ["CPU Boost", "Enabled"],
        ["Cooling", "Aggressive"],
        ["Background", "Reduced"],
        ["Memory Policy", "Normal"]
      ]
    },
    {
      key: "gaming",
      icon: "",
      name: "Gaming",
      tag: "Low latency",
      subtitle: "Low-latency gaming with consistent frame times.",
      // "if installed" is honest in both worlds: gamemode is an optional
      // dependency, so the chip never promises a tweak that isn't there and
      // never reads as a failure either.
      chips: ["NVIDIA", "GameMode if installed"],
      profile: 80,
      config: [
        ["CPU Policy", "Performance"],
        ["GPU Policy", "NVIDIA"],
        ["CPU Boost", "Enabled"],
        ["GameMode", "GameMode"],
        ["Cooling", "Aggressive"],
        ["Background", "Minimized"],
        ["Memory Policy", "Normal"]
      ]
    },
    {
      key: "ai",
      icon: "󰋛",
      name: "AI",
      tag: "Local inference",
      subtitle: "Local AI inference scaled to 4 GB VRAM + 15 GB RAM.",
      chips: ["NVIDIA compute", "RAM-friendly"],
      profile: 92,
      config: [
        ["CPU Policy", "Sustained performance"],
        ["GPU Policy", "NVIDIA"],
        ["CPU Boost", "Enabled"],
        ["Ollama", "Optimized"],
        ["Cooling", "Aggressive"],
        ["Background", "Reduced"],
        ["Memory Policy", "Protected"]
      ]
    }
  ]

  function def(key) {
    for (var i = 0; i < data.length; i++)
      if (data[i].key === key) return data[i];
    return data[1];
  }

  readonly property var keys: ["silent", "balanced", "performance", "gaming", "ai"]
}