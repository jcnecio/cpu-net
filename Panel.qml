import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Details panel for the System & Network bar widget. Replaces the old waybar
// Pango tooltip with a native Quickshell surface: CPU/GPU/memory/swap/disk
// meters, the top processes, and live network traffic.
//
// BarWidget.qml owns data polling and injects `bar`, `settings`, `anchorItem`,
// and `hostWidget`; this panel only renders what the host widget has collected.
Panel {
  id: root
  moduleName: "cpu-net"
  ipcTarget: "cpu-net"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so the popout coordinator and panel switching must key off
  // the host widget.
  readonly property var barIdentity: hostWidget || root

  readonly property var sys: root.hostWidget ? root.hostWidget.sysData : null
  readonly property var net: root.hostWidget ? root.hostWidget.netData : null

  readonly property bool hasGpu: root.sys
    && root.sys.gpu !== null && root.sys.gpu !== undefined
    && isFinite(Number(root.sys.gpu))
  readonly property bool hasGpuMem: root.sys
    && root.sys.gpuMemUsed !== null && root.sys.gpuMemTotal !== null
    && root.sys.gpuMemTotal > 0

  // Guarded so the panel renders before the bar is injected.
  readonly property color contentForeground: root.barForeground
  readonly property color dim: Qt.darker(root.barForeground, 1.4)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(1000))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelScroll
        anchors.fill: parent
        contentWidth: contentColumn.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: panelScroll.width
          spacing: Style.space(14)

          // ---- Hero: title, uptime, online status
          PanelHero {
            width: parent.width
            title: "System & Network"
            meta: root.sys ? root.sys.uptime : "Collecting…"
            detail: root.net && root.net.connected ? "ONLINE" : ""
            iconComponent: Component {
              Text {
                text: "󰻠"
                color: Model.COLORS.cpu
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // ---- Meters
          PanelSeparator {
            foreground: root.contentForeground
          }

          MeterRow {
            icon: Model.ICONS.cpu
            iconColor: Model.COLORS.cpu
            label: "CPU"
            percent: root.sys ? Model.clampPercent(root.sys.cpu) : 0
          }

          MeterRow {
            visible: root.hasGpu
            icon: Model.ICONS.gpu
            iconColor: Model.COLORS.gpu
            label: "GPU"
            percent: root.sys ? Model.clampPercent(root.sys.gpu) : 0
            caption: root.hasGpuMem
              ? "VRAM: " + Model.fmtBytes(root.sys.gpuMemUsed) + " │ Total: " + Model.fmtBytes(root.sys.gpuMemTotal)
              : (root.sys && root.sys.gpuName ? root.sys.gpuName : "")
          }

          MeterRow {
            icon: Model.ICONS.mem
            iconColor: Model.COLORS.mem
            label: "MEMORY"
            percent: root.sys ? Model.clampPercent(root.sys.memPercent) : 0
            caption: root.sys
              ? "Used: " + Model.fmtBytes(root.sys.memUsed) + " │ Total: " + Model.fmtBytes(root.sys.memTotal)
              : ""
          }

          MeterRow {
            icon: "󰓅"
            iconColor: Model.COLORS.up
            label: "SWAP"
            percent: root.sys ? Model.clampPercent(root.sys.swapPercent) : 0
          }

          MeterRow {
            icon: "󰋊"
            iconColor: Model.COLORS.cpu
            label: "DISK"
            percent: root.sys ? Model.clampPercent(root.sys.diskPercent) : 0
            caption: root.sys
              ? "Used: " + Model.fmtBytes(root.sys.diskUsed) + " │ Total: " + Model.fmtBytes(root.sys.diskTotal)
              : ""
          }

          // ---- Top processes
          PanelSeparator {
            foreground: root.contentForeground
          }

          PanelSectionHeader {
            text: "ACTIVE TASKS"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(5)
            visible: root.sys && root.sys.processes && root.sys.processes.length > 0

            Repeater {
              model: root.sys ? root.sys.processes : []

              ProcessRow {
                required property var modelData
                name: modelData[0]
                memory: Model.fmtBytes(modelData[1])
              }
            }
          }

          // ---- Network traffic
          PanelSeparator {
            foreground: root.contentForeground
          }

          PanelSectionHeader {
            text: "NETWORK TRAFFIC"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(5)

            NetRow {
              icon: "󰤨"
              label: "INTERFACE"
              value: root.net && root.net.interface ? String(root.net.interface).toUpperCase() : "—"
              color: Model.COLORS.label
            }
            NetRow {
              icon: Model.ICONS.down
              label: "DOWNLOAD"
              value: root.net ? Model.fmtRate(root.net.downKBs) + "/s" : "—"
              color: Model.COLORS.down
            }
            NetRow {
              icon: Model.ICONS.up
              label: "UPLOAD"
              value: root.net ? Model.fmtRate(root.net.upKBs) + "/s" : "—"
              color: Model.COLORS.up
            }
            NetRow {
              icon: "󰇘"
              label: "LATENCY"
              value: (root.net && root.net.pingMs !== null && root.net.pingMs !== undefined)
                ? Number(root.net.pingMs) + "ms" : "—"
              color: Model.COLORS.ping
            }
            NetRow {
              icon: "󰄬"
              label: "STATUS"
              value: root.net ? (root.net.connected ? "CONNECTED" : "DISCONNECTED") : "—"
              color: root.net && root.net.connected ? Model.COLORS.down : Model.COLORS.gpu
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  // ---- Section meter: icon + label + percent, then [■■■□□□□□□□] + caption
  component MeterRow: Column {
    id: meter
    required property string icon
    required property color iconColor
    required property string label
    required property int percent
    property string caption: ""
    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: Math.max(headerIcon.implicitHeight, headerLabel.implicitHeight, headerPct.implicitHeight)

      Text {
        id: headerIcon
        text: meter.icon
        color: meter.iconColor
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        width: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: headerLabel
        text: meter.label
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.left: headerIcon.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: headerPct
        text: meter.percent + "%"
        color: root.dim
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Text {
      width: parent.width
      text: "[" + Model.blockBar(meter.percent) + "]"
        + (meter.caption !== "" ? "   " + meter.caption : "")
      color: root.dim
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  // ---- Top-process row: name left, memory right.
  component ProcessRow: Item {
    id: processRow
    required property string name
    required property string memory
    width: parent ? parent.width : 0
    implicitHeight: Math.max(nameText.implicitHeight, memText.implicitHeight)

    Text {
      id: nameText
      text: String(processRow.name).toUpperCase().slice(0, 15)
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      width: parent.width - memText.implicitWidth - Style.space(12)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: memText
      text: processRow.memory
      color: root.dim
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // ---- Network key/value row: icon + colored label left, value right.
  component NetRow: Item {
    id: netRow
    required property string icon
    required property string label
    required property string value
    required property color color
    width: parent ? parent.width : 0
    implicitHeight: Math.max(iconText.implicitHeight, labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: iconText
      text: netRow.icon
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      width: Style.space(20)
      horizontalAlignment: Text.AlignHCenter
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: labelText
      text: netRow.label
      color: netRow.color
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      anchors.left: iconText.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: valueText
      text: netRow.value
      color: root.dim
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
