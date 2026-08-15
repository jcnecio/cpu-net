// Shared formatting helpers for the cpu-net bar widget and panel.
// Pure JS: no Qt dependencies, safe to unit test under node.
//
// The original waybar scripts styled everything with Pango markup; here the
// data flows in as plain numbers and Model returns structured "parts"
// ({ icon, color, text }) that the QML renders with native Text colors.

// Catppuccin Mocha — the exact palette the waybar scripts hardcoded.
const COLORS = {
  cpu: "#89b4fa",       // blue
  gpu: "#f38ba8",       // red
  mem: "#a6e3a1",       // green
  down: "#a6e3a1",      // green (steady download)
  downIdle: "#45475a",  // surface0 (no traffic)
  downHot: "#f38ba8",   // red (heavy download)
  up: "#fab387",        // peach
  ping: "#f9e2af",      // yellow
  border: "#cba6f7",    // mauve
  label: "#cba6f7",     // mauve
  value: "#dcd6d6",     // subtext1
  text: "#cdd6f4"       // text
}

const ICONS = {
  cpu: "󰻠",
  gpu: "󰾲",
  mem: "󰍛",
  down: "󰇚",
  up: "󰕒"
}

function parseJson(raw) {
  try {
    return JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
}

function clampPercent(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  return Math.max(0, Math.min(100, Math.round(n)))
}

// Bytes to "12.3GB" / "1.2MB", matching the original fmt().
function fmtBytes(bytes) {
  var v = Number(bytes)
  if (!isFinite(v) || v < 0) return "0.0B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  for (var i = 0; i < units.length; i++) {
    if (v < 1024) return v.toFixed(1) + units[i]
    v /= 1024
  }
  return v.toFixed(1) + "PB"
}

// Rate in KB/s to "1.2M" / "340K", matching the original fmt().
function fmtRate(kbs) {
  var v = Number(kbs)
  if (!isFinite(v) || v < 0) return "0K"
  if (v >= 1024) return (v / 1024).toFixed(1) + "M"
  return Math.round(v) + "K"
}

// Visual bar like the original: [■■■■■□□□□□]
function blockBar(percent, length) {
  var len = length || 10
  var filled = Math.round(len * clampPercent(percent) / 100)
  var s = ""
  for (var i = 0; i < len; i++) s += (i < filled ? "■" : "□")
  return s
}

// Bar text parts from system_info.py output: CPU / GPU? / RAM.
function sysParts(sys) {
  if (!sys) return []
  var parts = []
  parts.push({ icon: ICONS.cpu, color: COLORS.cpu, text: clampPercent(sys.cpu) + "%" })
  if (sys.gpu !== null && sys.gpu !== undefined && isFinite(Number(sys.gpu))) {
    parts.push({ icon: ICONS.gpu, color: COLORS.gpu, text: clampPercent(sys.gpu) + "%" })
  }
  parts.push({ icon: ICONS.mem, color: COLORS.mem, text: clampPercent(sys.memPercent) + "%" })
  return parts
}

// Bar text parts from net_speed.sh output: download (with equalizer glyph) + upload.
function netParts(net) {
  if (!net) return []
  var down = Math.max(0, Number(net.downKBs) || 0)
  var up = Math.max(0, Number(net.upKBs) || 0)

  var downColor = down === 0 ? COLORS.downIdle : (down < 500 ? COLORS.down : COLORS.downHot)
  var eq = down === 0 ? "" : (down < 500 ? "▂" : "▇")

  return [
    { icon: (ICONS.down + (eq ? " " + eq : "")), color: downColor, text: fmtRate(down) },
    { icon: ICONS.up, color: COLORS.up, text: fmtRate(up) }
  ]
}

// Join parts into a plain "󰻠 32%  󰍛 45%" string (tooltip / fallback).
function barText(parts) {
  var out = []
  for (var i = 0; i < parts.length; i++) out.push(parts[i].icon + " " + parts[i].text)
  return out.join("  ")
}

// Concise plain-text summary for the bar tooltip (rich detail lives in Panel.qml).
function summary(sys, net) {
  var lines = []
  var chips = []
  if (sys) {
    chips.push("CPU " + clampPercent(sys.cpu) + "%")
    if (sys.gpu !== null && sys.gpu !== undefined && isFinite(Number(sys.gpu)))
      chips.push("GPU " + clampPercent(sys.gpu) + "%")
    chips.push("MEM " + clampPercent(sys.memPercent) + "%")
  }
  if (chips.length > 0) lines.push(chips.join(" · "))
  if (net) {
    var down = Math.max(0, Number(net.downKBs) || 0)
    var up = Math.max(0, Number(net.upKBs) || 0)
    var netLine = "↓ " + fmtRate(down) + "/s   ↑ " + fmtRate(up) + "/s"
    if (net.pingMs !== null && net.pingMs !== undefined && isFinite(Number(net.pingMs)))
      netLine += "   ping " + Number(net.pingMs) + "ms"
    lines.push(netLine)
  }
  return lines.join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    COLORS: COLORS,
    ICONS: ICONS,
    parseJson: parseJson,
    clampPercent: clampPercent,
    fmtBytes: fmtBytes,
    fmtRate: fmtRate,
    blockBar: blockBar,
    sysParts: sysParts,
    netParts: netParts,
    barText: barText,
    summary: summary
  }
}
