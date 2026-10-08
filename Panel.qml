import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Timur popup: quick time entry + journal note, and the pill label.
// All network work happens in bin/timur-bar (next to this file); this file
// reads its state.json and runs it for saves.
Panel {
  id: root
  moduleName: "crsstha.timur"
  ipcTarget: "crsstha.timur"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The script ships inside the plugin folder (bin/timur-bar).
  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/timur-bar")).replace(/^file:\/\//, ""))
  readonly property int nudgeHour: 17
  readonly property int nudgeMinutes: 120
  readonly property int expiryWarnDays: 3
  readonly property int maxTaskRows: 4

  // ---- data from state.json
  property var data: ({})
  property date now: new Date()
  readonly property string todayIso: isoDate(now)
  readonly property string dayIso: isoDate(new Date(now.getFullYear(), now.getMonth(), now.getDate() + dayOffset))
  readonly property var day: (data.days && data.days[dayIso]) ? data.days[dayIso] : ({ entries: [], totalMinutes: 0, journal: "" })
  readonly property int todayMinutes: (data.days && data.days[todayIso]) ? data.days[todayIso].totalMinutes : 0
  readonly property bool hasData: !!data.days
  readonly property bool needsSession: data.errorKind === "auth"
  readonly property real expiryDays: data.me && data.me.loginExpire ? (new Date(data.me.loginExpire) - now) / 86400000 : 999
  readonly property bool expiringSoon: !needsSession && expiryDays < expiryWarnDays
  readonly property bool nudge: !needsSession && hasData && now.getHours() >= nudgeHour && todayMinutes < nudgeMinutes

  readonly property string label: needsSession ? "󰔟 !" : "󰔟 " + (hasData ? formatMinutes(todayMinutes) : "…") + (expiringSoon ? " •" : "")

  // ---- form state
  property string tab: "entry"          // "entry" | "journal"
  property int dayOffset: 0             // 0 today, -1 yesterday
  onDayOffsetChanged: { cancelEdit(); confirmDeleteId = "" }
  property string taskQuery: ""
  property string selectedTaskId: ""
  property int taskCursor: 0
  property string entryType: ""
  property string entryStatus: "DONE"
  property string durationText: ""
  property string description: ""
  property string noteText: ""
  property bool busy: false
  // Editing an existing entry: its clientId (empty when adding a new one)
  property string editingClientId: ""
  property string editingTaskLabel: ""  // fallback when the task is no longer active
  property string confirmDeleteId: ""   // clientId of the row asking "Delete?"
  property string message: ""
  property string messageKind: ""       // "ok" | "error" | "auth"

  readonly property int durationMinutes: parseDuration(durationText)
  readonly property var taskMatches: filterTasks(taskQuery)
  readonly property string selectedTaskLabel: taskLabelFor(selectedTaskId) || (editingClientId !== "" ? editingTaskLabel : "")
  readonly property bool editing: editingClientId !== ""
  readonly property bool canSave: !busy && selectedTaskId !== "" && entryType !== "" && durationMinutes > 0

  // ---- lifecycle
  function open() { openTab(root.tab) }
  function openFromHotkey() { open() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function openTab(which) {
    root.tab = which
    if (!root.opened) {
      root.message = ""
      root.controller.show()
      root.refresh()
    }
    Qt.callLater(root.focusCurrentTab)
  }

  function focusCurrentTab() {
    if (root.tab === "entry") taskField.forceActiveFocus()
    else noteField.forceActiveFocus()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ---- helpers
  function isoDate(d) { return Qt.formatDate(d, "yyyy-MM-dd") }

  function formatMinutes(m) {
    m = Math.round(m || 0)
    var h = Math.floor(m / 60), r = m % 60
    if (h === 0) return r + "m"
    return h + "h" + (r ? (r < 10 ? "0" : "") + r : "")
  }

  // Hours by default: 1 · 1.5 · .5 · 2h · 1h30 · 1:30; minutes only with "m": 45m  →  minutes (0 if invalid)
  function parseDuration(text) {
    var minutes = parseDurationRaw(text)
    return minutes > 0 && minutes <= 24 * 60 ? minutes : 0  // over a day is surely a typo
  }

  function parseDurationRaw(text) {
    var s = String(text || "").trim().toLowerCase().replace(/\s+/g, "")
    if (s === "") return 0
    var m
    if ((m = s.match(/^(\d+):([0-5]\d)$/))) return parseInt(m[1]) * 60 + parseInt(m[2])
    if ((m = s.match(/^(\d+(?:\.\d+)?)h(?:(\d+)m?)?$/))) return Math.round(parseFloat(m[1]) * 60) + (m[2] ? parseInt(m[2]) : 0)
    if ((m = s.match(/^(\d+)m$/))) return parseInt(m[1])
    if ((m = s.match(/^(\d*\.?\d+)$/))) return Math.round(parseFloat(m[1]) * 60)
    return 0
  }

  function taskLabelFor(id) {
    var tasks = data.tasks || []
    for (var i = 0; i < tasks.length; i++) if (String(tasks[i].id) === String(id)) return tasks[i].label
    return ""
  }

  function filterTasks(query) {
    var tasks = data.tasks || []
    var recent = data.recentTaskIds || []
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function(w) { return w !== "" })
    var matches = tasks.filter(function(t) {
      var label = t.label.toLowerCase()
      return words.every(function(w) { return label.indexOf(w) !== -1 })
    }).map(function(t) {
      var r = recent.indexOf(String(t.id))
      return { id: String(t.id), label: t.label, recent: r !== -1, rank: r === -1 ? 9999 : r }
    })
    matches.sort(function(a, b) { return a.rank - b.rank || a.label.localeCompare(b.label) })
    return matches.slice(0, maxTaskRows)
  }

  function pickTask(id) {
    root.selectedTaskId = id
    var last = data.lastTypeByTask ? data.lastTypeByTask[id] : ""
    root.entryType = last || root.entryType || defaultType()
    durationField.forceActiveFocus()
  }

  function defaultType() {
    var types = data.types || []
    for (var i = 0; i < types.length; i++) if (types[i].key === "DEVELOPMENT") return "DEVELOPMENT"
    return types.length ? types[0].key : ""
  }

  function enumOptions(list) {
    return (list || []).map(function(e) { return { value: e.key, label: e.label } })
  }

  // ---- actions
  function refresh() {
    runCli(["refresh"], false)
  }

  function saveEntry() {
    if (!canSave) {
      if (selectedTaskId === "") showMessage("Pick a task first", "error")
      else if (durationMinutes <= 0) showMessage("Enter a duration in hours, like 1, 1.5 or 0.25 (or 45m)", "error")
      return
    }
    var fields = {
      date: root.dayIso, task: root.selectedTaskId, type: root.entryType,
      status: root.entryStatus, duration: root.durationMinutes, description: root.description.trim()
    }
    if (root.editing) {
      fields.clientId = root.editingClientId
      runCli(["update-entry", JSON.stringify(fields)], true, "update")
    } else {
      runCli(["add-entry", JSON.stringify(fields)], true, "entry")
    }
  }

  // Load a logged entry into the form; Save then updates it in place.
  function startEdit(entry) {
    root.confirmDeleteId = ""
    root.editingClientId = entry.clientId || ""
    root.editingTaskLabel = entry.task || ""
    root.selectedTaskId = String(entry.taskId || "")
    root.entryType = entry.type || defaultType()
    root.entryStatus = entry.status || "DONE"
    root.durationText = entry.duration ? formatMinutes(entry.duration) : ""
    root.description = entry.description || ""
    root.taskQuery = ""
    showMessage(entry.clientId ? "" : "This entry has no clientId — edit it in the web app", entry.clientId ? "" : "error")
    descriptionField.forceActiveFocus()
  }

  function cancelEdit() {
    if (!root.editing) return
    root.editingClientId = ""
    root.editingTaskLabel = ""
    root.selectedTaskId = ""
    root.durationText = ""
    root.description = ""
    root.entryStatus = "DONE"
    showMessage("", "")
  }

  function deleteEntry(entry) {
    root.confirmDeleteId = ""
    if (root.editingClientId === entry.clientId) cancelEdit()
    root.pendingSummary = root.formatMinutes(entry.duration) + " · " + entry.task
    runCli(["delete-entry", entry.clientId, root.dayIso], true, "delete")
  }

  function addNote() {
    if (busy || noteText.trim() === "") return
    runCli(["add-note", root.dayIso, root.noteText.trim()], true, "note")
  }

  function pasteSession() {
    Quickshell.execDetached([root.cli, "set-session", "--window"])
    root.close()
  }

  function showMessage(text, kind) {
    root.message = text
    root.messageKind = kind
  }

  property string pendingAction: ""
  property string pendingSummary: ""
  function runCli(args, isSave, action) {
    if (proc.running) return
    root.pendingAction = action || ""
    if (isSave) {
      root.busy = true
      showMessage("Saving…", "")
    }
    proc.command = [root.cli].concat(args)
    proc.running = true
  }

  function finishCli(output) {
    var result = {}
    try { result = JSON.parse(String(output).trim().split("\n").pop() || "{}") }
    catch (e) { result = { ok: false, error: "Unexpected output from timur-bar" } }
    var action = root.pendingAction
    root.pendingAction = ""
    root.busy = false
    if (action === "") return  // refresh problems show in the header block
    if (!result.ok) {
      showMessage((result.errorKind === "network" ? "Not saved — " : "") + (result.error || "Save failed") + ". Your input is kept.",
                  result.errorKind === "auth" ? "auth" : "error")
      return
    }
    if (action === "entry") {
      var summary = "Logged " + formatMinutes(root.durationMinutes) + " to " + root.selectedTaskLabel
      showMessage("✓ " + summary, "ok")
      Quickshell.execDetached(["notify-send", "--app-name=Timur", "--icon=appointment-new", "Timur", summary])
      root.durationText = ""
      root.description = ""
      root.taskQuery = ""
      taskField.forceActiveFocus()
    } else if (action === "update") {
      var updated = "Updated " + formatMinutes(root.durationMinutes) + " · " + root.selectedTaskLabel
      showMessage("✓ " + updated, "ok")
      Quickshell.execDetached(["notify-send", "--app-name=Timur", "--icon=document-edit", "Timur", updated])
      root.editingClientId = ""
      root.editingTaskLabel = ""
      root.durationText = ""
      root.description = ""
      root.taskQuery = ""
      taskField.forceActiveFocus()
    } else if (action === "delete") {
      showMessage("✓ Deleted " + root.pendingSummary, "ok")
      Quickshell.execDetached(["notify-send", "--app-name=Timur", "--icon=edit-delete", "Timur", "Deleted " + root.pendingSummary])
    } else if (action === "note") {
      showMessage("✓ Added to " + (root.dayOffset === 0 ? "today's" : "yesterday's") + " journal", "ok")
      root.noteText = ""
      noteField.forceActiveFocus()
    }
  }

  Process {
    id: proc
    stdout: StdioCollector {
      id: procOut
      waitForEnd: true
    }
    onExited: root.finishCli(procOut.text)
  }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.cache/timur-bar/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.data = JSON.parse(text()) } catch (e) {}
      if (root.entryType === "") root.entryType = root.defaultType()
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.now = new Date()
      stateFile.reload()
    }
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function entry(): void { root.openTab("entry") }
    function journal(): void { root.openTab("journal") }
    function refresh(): void { root.refresh() }
  }

  // ---- small building blocks
  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: Qt.darker(root.bar.foreground, 1.5)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.letterSpacing: 1
  }

  component Hairline: Rectangle {
    width: parent ? parent.width : 0
    height: Style.spacing.hairline
    color: root.bar.foreground
    opacity: 0.12
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: scope
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    FocusScope {
      id: scope
      anchors.fill: parent

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.confirmDeleteId !== "") root.confirmDeleteId = ""
          else if (root.editing) root.cancelEdit()
          else root.close()
          event.accepted = true
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
          if (root.tab === "entry") root.saveEntry()
          else root.addNote()
          event.accepted = true
        }
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: scroller.width
          spacing: Style.space(10)

          // ---- Header
          Item {
            width: parent.width
            height: Math.max(heading.implicitHeight, dayPicker.implicitHeight)

            Text {
              id: heading
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Timur"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.hasData ? (root.dayOffset === 0 ? "Today " : "Yesterday ") + root.formatMinutes(root.day.totalMinutes) : ""
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Button {
              id: refreshButton
              anchors.right: dayPicker.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "↻"
              tooltipText: "Refresh"
              foreground: root.bar.foreground
              iconSpinning: proc.running && root.pendingAction === ""
              onClicked: root.refresh()
            }
            ButtonGroup {
              id: dayPicker
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              focusable: false
              foreground: root.bar.foreground
              fontSize: Style.font.bodySmall
              options: [{ value: "-1", label: "Yesterday" }, { value: "0", label: "Today" }]
              value: String(root.dayOffset)
              onChanged: function(v) { root.dayOffset = parseInt(v) }
            }
          }

          // ---- Not connected / session problems
          Column {
            visible: root.needsSession || !root.hasData || root.expiringSoon
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.needsSession || !root.hasData
                ? (root.data.error || "Not connected.") + "\nCopy the __Secure-timur-PROD-sessionid and timur-PROD-csrftoken cookies from the Timur web app (F12 → Application → Cookies)."
                : "⚠ Timur session expires in " + Math.max(0, Math.floor(root.expiryDays)) + " day(s) — paste a new one soon."
              color: root.needsSession ? Color.urgent : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }
            Button {
              text: root.needsSession || !root.hasData ? "Paste session" : "Update session"
              bordered: true
              foreground: root.bar.foreground
              onClicked: root.pasteSession()
            }
          }

          Item {
            visible: root.hasData
            width: parent.width
            height: tabs.implicitHeight

            ButtonGroup {
              id: tabs
              focusable: false
              foreground: root.bar.foreground
              options: [{ value: "entry", label: "Time entry" }, { value: "journal", label: "Journal note" }]
              value: root.tab
              onChanged: function(v) { root.tab = v; Qt.callLater(root.focusCurrentTab) }
            }
          }

          Hairline { visible: root.hasData }

          // ================= Time entry tab
          Column {
            visible: root.hasData && root.tab === "entry"
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              visible: root.editing
              width: parent.width
              height: editingBanner.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.bar.foreground, Color.accent)

              Text {
                id: editingBanner
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "✎ Editing a logged entry — Save updates it, Esc cancels"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            SectionLabel { text: "TASK" + (root.selectedTaskLabel ? "   ·   " + root.selectedTaskLabel : "") }

            TextField {
              id: taskField
              width: parent.width
              placeholderText: "Search tasks…"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              text: root.taskQuery
              onTextEdited: { root.taskQuery = text; root.taskCursor = 0 }
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                  root.taskCursor = Math.min(root.taskCursor + 1, root.taskMatches.length - 1); event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                  root.taskCursor = Math.max(root.taskCursor - 1, 0); event.accepted = true
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ControlModifier)) {
                  if (root.taskMatches.length) root.pickTask(root.taskMatches[root.taskCursor].id)
                  event.accepted = true
                }
              }
              KeyNavigation.tab: durationField
            }

            Column {
              width: parent.width
              spacing: 0

              Repeater {
                model: root.taskMatches

                Rectangle {
                  required property var modelData
                  required property int index
                  readonly property bool chosen: modelData.id === root.selectedTaskId
                  readonly property bool hot: index === root.taskCursor || rowArea.containsMouse
                  width: parent.width
                  height: rowLabel.implicitHeight + Style.space(8)
                  radius: Style.cornerRadius
                  color: hot ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"

                  Text {
                    id: rowLabel
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    anchors.right: recentTag.left
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: (parent.chosen ? "▸ " : "  ") + modelData.label
                    color: parent.chosen ? Color.accent : root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    id: recentTag
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.recent ? "recent" : ""
                    color: Qt.darker(root.bar.foreground, 1.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickTask(modelData.id)
                  }
                }
              }

              Text {
                visible: root.taskMatches.length === 0
                text: "No matching active tasks"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(16)

              Column {
                spacing: Style.space(4)
                SectionLabel { text: "TYPE" }
                Dropdown {
                  width: Style.space(190)
                  showLabel: false
                  options: root.enumOptions(root.data.types)
                  value: root.entryType
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  onChanged: function(v) { root.entryType = v }
                }
              }

              Column {
                spacing: Style.space(4)
                SectionLabel { text: "STATUS" }
                ButtonGroup {
                  focusable: false
                  foreground: root.bar.foreground
                  fontSize: Style.font.bodySmall
                  options: root.enumOptions((root.data.statuses || []).slice().sort(function(a, b) {
                    return ["TODO", "DOING", "DONE"].indexOf(a.key) - ["TODO", "DOING", "DONE"].indexOf(b.key)
                  }))
                  value: root.entryStatus
                  onChanged: function(v) { root.entryStatus = v }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(16)

              Column {
                spacing: Style.space(4)
                SectionLabel {
                  text: "DURATION" + (root.durationText !== "" ? (root.durationMinutes > 0 ? "  = " + root.formatMinutes(root.durationMinutes) : "  ?") : "")
                  color: root.durationText !== "" && root.durationMinutes <= 0 ? Color.urgent : Qt.darker(root.bar.foreground, 1.5)
                }
                TextField {
                  id: durationField
                  width: Style.space(110)
                  placeholderText: "hrs, e.g. 1.5"
                  foreground: root.bar.foreground
                  font.family: root.bar.fontFamily
                  text: root.durationText
                  onTextEdited: root.durationText = text
                  onAccepted: descriptionField.forceActiveFocus()
                  KeyNavigation.tab: descriptionField
                  KeyNavigation.backtab: taskField
                }
              }

              Column {
                width: parent.width - Style.space(126)
                spacing: Style.space(4)
                SectionLabel { text: "DESCRIPTION" }
                TextField {
                  id: descriptionField
                  width: parent.width
                  placeholderText: "What did you do?"
                  foreground: root.bar.foreground
                  font.family: root.bar.fontFamily
                  text: root.description
                  onTextEdited: root.description = text
                  onAccepted: root.saveEntry()
                  KeyNavigation.tab: taskField
                  KeyNavigation.backtab: durationField
                }
              }
            }

            Item {
              width: parent.width
              height: saveButton.implicitHeight

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: root.editing ? cancelEditButton.left : saveButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                text: root.tab === "entry" ? root.message : ""
                color: root.messageKind === "ok" ? Color.accent : (root.messageKind === "" ? root.bar.foreground : Color.urgent)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Button {
                id: cancelEditButton
                visible: root.editing
                anchors.right: saveButton.left
                anchors.rightMargin: Style.space(6)
                text: "Cancel"
                bordered: true
                enabled: !root.busy
                foreground: root.bar.foreground
                onClicked: root.cancelEdit()
              }
              Button {
                id: saveButton
                anchors.right: parent.right
                text: root.busy ? "Saving…" : (root.editing ? "Update" : "Save")
                bordered: true
                enabled: root.canSave
                foreground: root.bar.foreground
                onClicked: root.saveEntry()
              }
            }

            Hairline {}

            Item {
              width: parent.width
              height: loggedLabel.implicitHeight
              SectionLabel { id: loggedLabel; text: "LOGGED " + (root.dayOffset === 0 ? "TODAY" : "YESTERDAY") }
              SectionLabel { anchors.right: parent.right; text: root.formatMinutes(root.day.totalMinutes) }
            }

            Repeater {
              model: root.day.entries || []

              Item {
                id: entryRow
                required property var modelData
                readonly property bool confirming: root.confirmDeleteId !== "" && root.confirmDeleteId === modelData.clientId
                readonly property bool beingEdited: root.editing && root.editingClientId === modelData.clientId
                readonly property bool showActions: (rowHover.hovered || confirming) && !root.busy && modelData.clientId !== ""
                width: parent.width
                height: Math.max(rowDuration.implicitHeight, actions.implicitHeight) + Style.space(4)

                HoverHandler { id: rowHover }

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: entryRow.beingEdited || entryRow.confirming || rowHover.hovered
                    ? Style.hoverFillFor(root.bar.foreground, entryRow.confirming ? Color.urgent : Color.accent) : "transparent"
                }

                Text {
                  id: rowDuration
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(44)
                  horizontalAlignment: Text.AlignRight
                  text: root.formatMinutes(entryRow.modelData.duration)
                  color: Qt.darker(root.bar.foreground, 1.3)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  id: rowTask
                  textFormat: Text.PlainText
                  anchors.left: rowDuration.right
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(190)
                  elide: Text.ElideMiddle
                  text: entryRow.modelData.task
                  color: entryRow.beingEdited ? Color.accent : root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  anchors.left: rowTask.right
                  anchors.leftMargin: Style.space(12)
                  anchors.right: entryRow.showActions ? actions.left : parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: entryRow.confirming ? "Delete this entry?" : entryRow.modelData.description
                  color: entryRow.confirming ? Color.urgent : Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body
                }

                Row {
                  id: actions
                  visible: entryRow.showActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Button {
                    visible: !entryRow.confirming
                    text: "Edit"
                    fontSize: Style.font.bodySmall
                    foreground: root.bar.foreground
                    onClicked: root.startEdit(entryRow.modelData)
                  }
                  Button {
                    visible: !entryRow.confirming
                    text: "Delete"
                    fontSize: Style.font.bodySmall
                    foreground: Color.urgent
                    onClicked: root.confirmDeleteId = entryRow.modelData.clientId
                  }
                  Button {
                    visible: entryRow.confirming
                    text: "Yes, delete"
                    bordered: true
                    fontSize: Style.font.bodySmall
                    foreground: Color.urgent
                    onClicked: root.deleteEntry(entryRow.modelData)
                  }
                  Button {
                    visible: entryRow.confirming
                    text: "Keep"
                    bordered: true
                    fontSize: Style.font.bodySmall
                    foreground: root.bar.foreground
                    onClicked: root.confirmDeleteId = ""
                  }
                }
              }
            }

            SectionLabel {
              visible: (root.day.entries || []).length === 0
              text: "Nothing logged yet"
              font.italic: true
              font.letterSpacing: 0
            }
          }

          // ================= Journal tab
          Column {
            visible: root.hasData && root.tab === "journal"
            width: parent.width
            spacing: Style.space(8)

            SectionLabel { text: "ADD TO " + (root.dayOffset === 0 ? "TODAY'S" : "YESTERDAY'S") + " JOURNAL" }

            TextField {
              id: noteField
              width: parent.width
              placeholderText: "What happened?"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              text: root.noteText
              onTextEdited: root.noteText = text
              onAccepted: root.addNote()
            }

            Item {
              width: parent.width
              height: addButton.implicitHeight

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: addButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: root.message !== "" ? root.message
                  : (root.noteText.trim() !== "" ? "Will be added as:  - " + Qt.formatTime(root.now, "HH:mm") + " " + root.noteText.trim() : "")
                color: root.messageKind === "ok" ? Color.accent
                  : (root.messageKind === "error" || root.messageKind === "auth" ? Color.urgent : Qt.darker(root.bar.foreground, 1.4))
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Button {
                id: addButton
                anchors.right: parent.right
                text: root.busy ? "Saving…" : "Add line"
                bordered: true
                enabled: !root.busy && root.noteText.trim() !== ""
                foreground: root.bar.foreground
                onClicked: root.addNote()
              }
            }

            Hairline {}

            SectionLabel { text: (root.dayOffset === 0 ? "TODAY'S" : "YESTERDAY'S") + " JOURNAL" }

            Flickable {
              width: parent.width
              height: Math.min(journalText.implicitHeight, Style.space(260))
              contentWidth: width
              contentHeight: journalText.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height
              onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

              Text {
                id: journalText
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: root.day.journal || "Empty"
                color: root.day.journal ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
                font.italic: !root.day.journal
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }
      }
    }
  }
}
