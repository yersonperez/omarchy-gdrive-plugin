import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool installed: false
  property bool running: false
  property bool authenticated: false

  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string statusText: "Checking…"
  property string accountPath: ""
  property string plan: ""
  property double usedBytes: 0
  property double quotaBytes: 0
  property double usagePercent: 0
  property bool quotaKnown: false
  property var files: []
  property var added: []
  property var removed: []
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
  readonly property bool busy: statusProcess.running || mountProcess.running
  readonly property string helperPath: {
    var url = Qt.resolvedUrl("status.py")
    var path = String(url)
    if (path.indexOf("file://") === 0) path = decodeURIComponent(path.substring(7))
    return path
  }

  property string _statusOutput: ""
  property string _statusError: ""
  property string _mountOutput: ""
  property string _mountError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["python3", helperPath, "25"]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to read Google Drive status"
      return
    }
    installed = parsed.installed === true
    running = parsed.running === true
    authenticated = parsed.authenticated === true
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    statusText = String(parsed.statusText || (installed ? "Stopped" : "Not installed"))
    accountPath = String(parsed.accountPath || "")
    plan = String(parsed.plan || "")
    usedBytes = Number(parsed.usedBytes || 0)
    quotaBytes = Number(parsed.quotaBytes || 0)
    usagePercent = Number(parsed.usagePercent || 0)
    quotaKnown = parsed.quotaKnown === true
    files = parsed.files || []
    added = parsed.added || []
    removed = parsed.removed || []
    lastError = ""
    notifyChanges(added, removed)
  }

  function notifyChanges(addedFiles, removedFiles) {
    if ((!addedFiles || addedFiles.length === 0) && (!removedFiles || removedFiles.length === 0)) return
    var lines = []
    if (addedFiles && addedFiles.length > 0) {
      for (var i = 0; i < addedFiles.length && i < 5; i++) {
        lines.push("Nuevo: " + String(addedFiles[i].name || ""))
      }
      if (addedFiles.length > 5) lines.push("+" + (addedFiles.length - 5) + " más")
    }
    if (removedFiles && removedFiles.length > 0) {
      if (lines.length > 0) lines.push("")
      for (var j = 0; j < removedFiles.length && j < 5; j++) {
        lines.push("Eliminado: " + String(removedFiles[j].name || ""))
      }
      if (removedFiles.length > 5) lines.push("+" + (removedFiles.length - 5) + " más")
    }
    var body = lines.join("\n")
    Quickshell.execDetached(["omarchy", "notification", "send", "-g", "󰊶", "--app-name", "yerson.gdrive", "Google Drive", body])
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function mount() {
    runControl(["systemctl", "--user", "start", "rclone-gdrive.service"], 1)
  }

  function unmount() {
    runControl(["systemctl", "--user", "stop", "rclone-gdrive.service"], 0)
  }

  function toggleMounted() {
    if (active) unmount()
    else mount()
  }

  function runControl(command, desired) {
    if (!installed || mountProcess.running) return
    _desired = desired
    _mountOutput = ""
    _mountError = ""
    mountProcess.command = command
    mountProcess.running = true
  }

  function openFile(file) {
    if (!file || !file.path) return
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--select", fileUri(String(file.path))])
  }

  function fileUri(path) {
    var parts = String(path || "").split("/")
    for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    return "file://" + parts.join("/")
  }

  function connect() {
    if (!installed || mountProcess.running) return
    actionStatus = "Opening Google Drive authorization…"
    mountProcess.command = ["bash", "-lc",
      "omarchy-launch-floating-terminal-with-presentation \"rclone config reconnect gdrive:\""]
    mountProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 1000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 4) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else root.lastError = root.elideStatus(stderr || stdout || "Could not read Google Drive status")
    }
  }

  Process {
    id: mountProcess
    running: false
    command: []
    stdout: StdioCollector { id: mountStdout; waitForEnd: true; onStreamFinished: root._mountOutput = text }
    stderr: StdioCollector { id: mountStderr; waitForEnd: true; onStreamFinished: root._mountError = text }
    onExited: function(exitCode) {
      var stdout = String(mountStdout.text || root._mountOutput || "")
      var stderr = String(mountStderr.text || root._mountError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(stderr || stdout || "Google Drive command failed")
        root.actionStatus = root.lastError
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      delayedRefresh.restart()
    }
  }
}