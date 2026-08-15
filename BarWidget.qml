import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// System & Network bar widget: CPU/GPU/memory percentages plus live network
// speed, polled from the bundled system_info.py and net_speed.sh scripts.
// Left click toggles the details panel (Panel.qml), right/middle click forces
// a refresh. The panel is loaded via a Loader and injected with the bar,
// settings, and anchor so Quattro's popout lifecycle applies.
BarWidget {
  id: root
  moduleName: "cpu-net"

  property var sysData: null
  property var netData: null
  property bool interactive: true
  property bool concealed: false

  // Resolve the bundled scripts from this plugin's own directory.
  readonly property string sysScript: Qt.resolvedUrl("system_info.py").toString().replace(/^file:\/\//, "")
  readonly property string netScript: Qt.resolvedUrl("net_speed.sh").toString().replace(/^file:\/\//, "")

  readonly property var parts: {
    var all = Model.sysParts(root.sysData).concat(Model.netParts(root.netData))
    // Vertical bars get a single compact slot: CPU only.
    return root.vertical ? all.slice(0, 1) : all
  }
  readonly property string barLabelText: Model.barText(parts)
  readonly property bool hasVisualContent: barLabelText !== ""

  // ---- Panel lifecycle. Shape contract for shell.summon/hide/toggle
  //      routing (Bar.findPanelWidget requires open/close/opened).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  // ---- Data polling -------------------------------------------------------

  function refresh() {
    if (!sysProc.running) sysProc.running = true
    if (!netProc.running) netProc.running = true
  }

  // ---- Custom bar button (multi-color parts, so no single-label WidgetButton)
  signal pressed(int button)

  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    if (button === Qt.LeftButton) root.toggle()
    root.pressed(button)
  }

  readonly property bool tooltipHovered: visible && interactive && !concealed && mouseArea.containsMouse

  function updateTooltip() {
    if (root.bar) root.bar.showTooltip(root, Model.summary(root.sysData, root.netData))
  }

  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }

  visible: hasVisualContent
  implicitWidth: contentRow.implicitWidth + Style.spaceReal(14)
  implicitHeight: barSize

  onBarChanged: syncClickRegistration()
  onSysDataChanged: updateTooltip()
  onNetDataChanged: updateTooltip()

  Component.onCompleted: {
    syncClickRegistration()
    refresh()
  }
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)

  onOpenedChanged: if (opened) refresh()

  Timer {
    id: pollTimer
    interval: Math.max(1000, Number(root.setting("interval", 2500)) || 2500)
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: sysProc
    command: ["python3", root.sysScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sysData = Model.parseJson(text)
    }
  }

  Process {
    id: netProc
    command: ["bash", root.netScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.netData = Model.parseJson(text)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName

    function refresh() { root.broadcast("refresh") }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: Style.space(7)

    Repeater {
      model: root.parts

      Text {
        required property var modelData
        text: modelData.icon + " " + modelData.text
        color: modelData.color
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: root.updateTooltip()
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton || mouse.button === Qt.MiddleButton) root.refresh()
      else root.triggerPress(mouse.button)
    }
  }
}
