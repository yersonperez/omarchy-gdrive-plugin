import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "yerson.gdrive"
  ipcTarget: "yerson.gdrive"
  manageIpc: false

  property string focusSection: "login"
  property int fileIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Cargando fotos",
    "Subiendo archivos",
    "Sincronizando carpetas",
    "Guardando documentos",
    "Moviendo memorias",
    "Ordenando bytes",
    "Empaquetando datos",
    "Transfiriendo cosas",
    "Editando hojas",
    "Archivando todo"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool lowSpace: gdrive.quotaKnown && gdrive.usagePercent >= 95
  readonly property color iconColor: gdrive.authenticated && gdrive.active ? foreground : dim
  readonly property string toggleHint: gdrive.active ? "Unmount Google Drive" : "Mount Google Drive"
  readonly property color barIconColor: gdrive.authenticated && gdrive.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && gdrive.installed

  function ensureCursor() {
    if (!gdrive.authenticated) {
      focusSection = "login"
      fileIndex = 0
      return
    }
    if (gdrive.files.length === 0) {
      focusSection = "header"
      fileIndex = 0
      return
    }
    if (focusSection !== "files" && focusSection !== "header") focusSection = "files"
    if (fileIndex >= gdrive.files.length) fileIndex = Math.max(0, gdrive.files.length - 1)
    if (fileIndex < 0) fileIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && gdrive.files.length > 0) {
        focusSection = "files"
        fileIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "files") {
      if (dy < 0 && fileIndex === 0) {
        setHeaderCursor()
        return
      }
      fileIndex = Math.max(0, Math.min(gdrive.files.length - 1, fileIndex + dy))
      scrollCursorIntoView()
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "files" && fileIndex < gdrive.files.length) {
      gdrive.openFile(gdrive.files[fileIndex])
    } else if (focusSection === "header") {
      gdrive.toggleMounted()
    } else if (focusSection === "login") {
      gdrive.connect()
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function setFileCursor(index) {
    cursorActive = true
    focusSection = "files"
    fileIndex = index
  }

  function scrollCursorIntoView() {
    if (focusSection === "files" && fileColumn && fileIndex >= 0 && fileIndex < fileColumn.children.length) {
      scrollItemIntoView(fileColumn.children[fileIndex])
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    gdrive.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onFileIndexChanged: scrollCursorIntoView()

  Service {
    id: gdrive
    settings: root.settings
  }

  Connections {
    target: gdrive
    function onAuthenticatedChanged() { root.ensureCursor() }
    function onFilesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { gdrive.refresh(); return "ok" }
    function mount(): string { gdrive.mount(); return "ok" }
    function unmount(): string { gdrive.unmount(); return "ok" }
    function status(): string { return gdrive.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰊶"
    active: root.lowSpace || (gdrive.authenticated && !gdrive.active)
    tooltipText: gdrive.active ? ("Google Drive · " + Model.usageText(gdrive.usedBytes, gdrive.quotaBytes, gdrive.quotaKnown)) : gdrive.statusText
    opacity: gdrive.authenticated && gdrive.active ? 1.0 : 0.6
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) gdrive.refresh()
      else if (buttonCode === Qt.MiddleButton) gdrive.toggleMounted()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") gdrive.refresh()
        else if (t === "m" || t === "M") gdrive.toggleMounted()
        else if (t === "l" || t === "L") gdrive.connect()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            visible: gdrive.authenticated
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Google Drive"
              meta: gdrive.active ? root.heroPhraseText : "Google Drive desmontado"
              detail: gdrive.active && root.lowSpace ? "Espacio casi lleno" : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: gdrive.active ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: "󰊶"
                  color: root.iconColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: gdrive.installed
                  checked: gdrive.active
                  busy: gdrive.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: gdrive.toggleMounted()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: gdrive.actionStatus !== "" || gdrive.lastError !== ""
            width: parent.width
            text: gdrive.actionStatus !== "" ? gdrive.actionStatus : gdrive.lastError
            color: gdrive.lastError !== "" && gdrive.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          LoginButton {
            visible: !gdrive.authenticated
            width: parent.width
          }

          Column {
            visible: gdrive.authenticated
            width: parent.width
            spacing: Style.spacing.labelGap

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap
              InfoPair { label: "Almacenado"; value: Model.usageText(gdrive.usedBytes, gdrive.quotaBytes, gdrive.quotaKnown) }
            }
          }

          PanelSeparator {
            visible: gdrive.authenticated
            foreground: root.foreground
          }

          Column {
            visible: gdrive.authenticated
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ARCHIVOS RECIENTES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: gdrive.files.length === 0
              width: parent.width
              text: "No se encontraron archivos recientes."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: fileColumn
              visible: gdrive.files.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: gdrive.files
                FileRow {
                  required property var modelData
                  required property int index
                  width: fileColumn.width
                  file: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && gdrive.authenticated && gdrive.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component LoginButton: CursorSurface {
    id: loginButton

    hasCursor: root.cursorActive && root.focusSection === "login"
    foreground: root.foreground

    implicitHeight: loginRow.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: gdrive.installed && !gdrive.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: gdrive.installed && !gdrive.busy
      onEntered: {
        root.cursorActive = true
        root.focusSection = "login"
      }
      onClicked: gdrive.connect()
    }

    RowLayout {
      id: loginRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰊶"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: gdrive.authenticated ? "Reautorizar Google Drive" : "Conectar Google Drive"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: gdrive.authenticated ? "Volver a autorizar la cuenta" : "Iniciar el flujo de autenticación"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰌋"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: gdrive.installed && !gdrive.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: gdrive.connect()
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow
    property var file: null
    property int rowIndex: 0
    readonly property string fileName: file ? String(file.name || "Untitled") : "Untitled"

    hasCursor: root.cursorActive && root.focusSection === "files" && root.fileIndex === rowIndex
    foreground: root.foreground

    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFileCursor(fileRow.rowIndex)
      onClicked: gdrive.openFile(fileRow.file)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: Model.fileGlyph(fileRow.fileName)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: fileRow.fileName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.fileMeta(fileRow.file)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}