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
  moduleName: "togglecorp.timur"
  ipcTarget: "togglecorp.timur"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The script ships inside the plugin folder (bin/timur-bar, one level up).
  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("../bin/timur-bar")).replace(/^file:\/\//, ""))
  readonly property int nudgeHour: 17
  readonly property int nudgeMinutes: 120
  readonly property int expiryWarnDays: 3
  readonly property int maxTaskRows: 4
  readonly property string webApp: "https://timur.dev.togglecorp.com/"

  // ---- data from state.json
  property var data: ({})
  property date now: new Date()
  readonly property string todayIso: isoDate(now)
  readonly property date dayDate: new Date(now.getFullYear(), now.getMonth(), now.getDate() + dayOffset)
  readonly property string dayIso: isoDate(dayDate)
  readonly property string dayName: dayOffset === 0 ? "Today" : dayOffset === -1 ? "Yesterday" : Qt.formatDate(dayDate, "ddd d MMM")
  readonly property bool dayLoaded: !!(data.days && data.days[dayIso])
  // Week strip: Monday..today totals from state.json ("week"); weekend days only when something was logged.
  readonly property real weekTarget: parseFloat(Quickshell.env("TIMUR_WEEK_TARGET")) || 40
  readonly property var weekDays: (data.week || []).filter(function(d) {
    var wd = new Date(d.date + "T00:00").getDay()
    return d.minutes > 0 || (wd !== 0 && wd !== 6)
  })
  readonly property int weekMinutes: (data.week || []).reduce(function(sum, d) { return sum + d.minutes }, 0)
  readonly property var day: (data.days && data.days[dayIso]) ? data.days[dayIso] : ({ entries: [], totalMinutes: 0, journal: "" })
  readonly property int todayMinutes: (data.days && data.days[todayIso]) ? data.days[todayIso].totalMinutes : 0
  readonly property bool hasData: !!data.days
  readonly property bool needsSession: data.errorKind === "auth"
  readonly property real expiryDays: data.me && data.me.loginExpire ? (new Date(data.me.loginExpire) - now) / 86400000 : 999
  readonly property bool expiringSoon: !needsSession && expiryDays < expiryWarnDays
  readonly property bool nudge: !needsSession && hasData && now.getHours() >= nudgeHour && todayMinutes < nudgeMinutes

  // ---- ▶ timer (~/.cache/timur-bar/timer.json, managed by `timur-bar timer`, shared with the i3 panel)
  property var timer: null
  readonly property bool timerPaused: !!(timer && timer.pausedAt)
  readonly property real timerSeconds: timer
    ? Math.max(0, (timer.pausedAt || now.getTime() / 1000) - timer.started - (timer.pausedSeconds || 0)) : 0
  readonly property string timerText: timer ? (timerPaused ? "⏸ " : "▶ ") + formatClock(timerSeconds) : ""

  readonly property string label: (needsSession ? "󰔟 !" : "󰔟 " + (hasData ? formatMinutes(todayMinutes) : "…") + (expiringSoon ? " •" : ""))
    + (timer ? "  " + timerText : "")

  // ---- form state
  property string tab: "entry"          // "entry" | "journal"
  property int dayOffset: 0             // 0 today, -1 yesterday, … (older days are fetched on demand)
  onDayOffsetChanged: {
    cancelEdit()
    confirmDeleteId = ""
    if (hasData && !dayLoaded) refresh()
  }
  property string fetchedIso: ""        // day asked for since the last good refresh, so a failing fetch doesn't loop
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

  // ---- Google Calendar meetings: days[…].meetings / .hidden in state.json, filled by `timur-bar refresh`
  readonly property bool calendarLinked: !!data.calendar
  readonly property string calendarError: data.calendarError || ""
  // Only meetings that have started: you can't log a meeting ahead. Set by updateMeetings only when they
  // change, not on every clock tick, so the rows (and what you're typing in them) aren't rebuilt each second.
  property var visibleMeetings: []
  property var hiddenMeetings: []
  onNowChanged: updateMeetings()
  onDayChanged: updateMeetings()
  property var meetingPicks: ({})       // meeting key -> { on, duration, task, type } chosen in the list
  property var pickingFor: null         // meeting keys, or "ticked", while the task search picks for meetings
  property bool showHidden: false       // the "N hidden" list (meetings marked not work) is open
  property string typeOpenKey: ""       // meeting whose type choices are shown under it
  property string problemKey: ""        // ticked meeting that Log scrolled to (missing task or time)
  readonly property int meetingRows: 6  // rows before Meetings scrolls
  readonly property int entryRows: 8    // rows before Logged scrolls
  readonly property var chosenMeetings: visibleMeetings.filter(function(m) { return pickFor(m).on })
  readonly property var meetingProblems: chosenMeetings.filter(function(m) {
    var p = pickFor(m)
    return !p.task || !p.type || parseDuration(p.duration) <= 0
  })
  readonly property bool allTicked: visibleMeetings.length > 0 && chosenMeetings.length === visibleMeetings.length
  readonly property int tickedWithoutTask: chosenMeetings.filter(function(m) { return !pickFor(m).task }).length
  // ---- ⚙ settings row and the confirmation it asks for
  property bool settingsOpen: false
  property string confirmAction: ""     // "session" | "calendar" while asking

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
  function formatClock(seconds) {
    var m = Math.floor(seconds / 60)
    return Math.floor(m / 60) + ":" + (m % 60 < 10 ? "0" : "") + (m % 60)
  }

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
    if (root.pickingFor) {  // the search was picking a task for meetings
      pickingKeys().forEach(function(key) { setMeetingTask(key, id) })
      stopTaskSearch()
      return
    }
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

  // ---- meetings
  function updateMeetings() {
    var started = function(m) { return new Date(m.start) <= root.now }
    var shown = (root.day.meetings || []).filter(started), hidden = (root.day.hidden || []).filter(started)
    if (JSON.stringify(shown) !== JSON.stringify(root.visibleMeetings)) root.visibleMeetings = shown
    if (JSON.stringify(hidden) !== JSON.stringify(root.hiddenMeetings)) root.hiddenMeetings = hidden
  }

  function shortTask(label) {  // "MapSwipe › Run Maintenance › RN Upgrade" -> "MapSwipe › RN Upgrade"
    var parts = String(label || "").split(" › ")
    var text = parts.length > 2 ? parts[0] + " › " + parts[parts.length - 1] : String(label || "")
    return text.length > 18 ? "…" + text.slice(text.length - 17) : text
  }

  function shortType(key) {  // "Meeting Internal" -> "Meet·I"
    var types = data.types || [], text = key || "Type"
    for (var i = 0; i < types.length; i++) if (types[i].key === key) text = types[i].label
    var words = text.split(/\s+/)
    return words[0].slice(0, 4) + (words.length > 1 ? "·" + words[1].charAt(0) : "")
  }

  function meetingType(taskId) {
    var keys = (data.types || []).map(function(t) { return t.key })
    var last = data.lastTypeByTask ? data.lastTypeByTask[String(taskId || "")] : ""
    return last || (keys.indexOf("INTERNAL_MEETING") !== -1 ? "INTERNAL_MEETING" : defaultType())
  }

  // Choices for a meeting; until touched, what was used for it before. One still going on, or
  // with no task yet, starts unticked.
  function pickFor(m) {
    var saved = root.meetingPicks[m.key]
    if (saved) return saved
    var suggest = m.suggest || {}
    return { on: new Date(m.end) <= root.now && !!suggest.task, duration: formatMinutes(m.minutes),
             task: String(suggest.task || ""), type: suggest.type || meetingType(suggest.task) }
  }

  function setPick(m, changes) {
    var picks = Object.assign({}, root.meetingPicks)
    picks[m.key] = Object.assign({}, pickFor(m), changes)
    root.meetingPicks = picks
    if (root.problemKey === m.key) root.problemKey = ""
  }

  function meetingByKey(key) {
    for (var i = 0; i < root.visibleMeetings.length; i++) if (root.visibleMeetings[i].key === key) return root.visibleMeetings[i]
    return null
  }

  // Choosing a task ticks the meeting and brings that task's usual type.
  function setMeetingTask(key, taskId) {
    var m = meetingByKey(key)
    if (m) setPick(m, taskId ? { task: taskId, type: meetingType(taskId), on: true } : { task: "" })
  }

  function tickAll(on) {
    var picks = Object.assign({}, root.meetingPicks)
    root.visibleMeetings.forEach(function(m) { picks[m.key] = Object.assign({}, pickFor(m), { on: on }) })
    root.meetingPicks = picks
  }

  function pickingKeys() {
    if (root.pickingFor === "ticked")
      return root.chosenMeetings.filter(function(m) { return !pickFor(m).task }).map(function(m) { return m.key })
    return root.pickingFor || []
  }

  // The TASK search picks a task for these meetings (Enter / click picks, Esc cancels).
  function startTaskSearch(keys) {
    root.pickingFor = keys
    root.taskQuery = ""
    root.taskCursor = 0
    taskField.forceActiveFocus()
  }

  function stopTaskSearch() {
    root.pickingFor = null
    root.taskQuery = ""
  }

  readonly property string pickingTitles: pickingKeys().map(function(k) { var m = meetingByKey(k); return m ? m.title : "" })
    .filter(function(t) { return t !== "" }).join(", ")

  readonly property string logMeetingsLabel: {
    if (root.busy && root.pendingAction === "meetings") return "Saving…"
    var text = root.chosenMeetings.length ? "Log " + root.chosenMeetings.length : "Log"
    var noTask = root.meetingProblems.filter(function(m) { var p = pickFor(m); return !p.task || !p.type }).length
    var noTime = root.meetingProblems.length - noTask
    if (noTask) return text + " · " + noTask + (noTask === 1 ? " needs" : " need") + " a task"
    if (noTime) return text + " · " + noTime + (noTime === 1 ? " needs" : " need") + " a time"
    return text
  }

  function logMeetings() {
    if (root.busy || !root.chosenMeetings.length) return
    if (root.meetingProblems.length) {  // show the first one instead of saving
      var m = root.meetingProblems[0], p = pickFor(m)
      root.problemKey = m.key
      var index = root.visibleMeetings.indexOf(m)
      meetingsFlick.contentY = Math.max(0, Math.min(index * meetingsFlick.rowHeight, meetingsFlick.contentHeight - meetingsFlick.height))
      showMessage("“" + m.title + "” needs a " + (!p.task || !p.type ? "task" : "time, like 30m or 1h"), "error")
      return
    }
    var fields = root.chosenMeetings.map(function(m) {
      var p = pickFor(m)
      return { date: root.dayIso, task: p.task, type: p.type, status: "DONE", duration: parseDuration(p.duration),
               description: m.title, startTime: m.start.slice(11, 16) + ":00", uid: m.uid, title: m.title }
    })
    root.pendingSummary = fields.length + (fields.length === 1 ? " meeting" : " meetings")
    runCli(["log-meetings", JSON.stringify(fields)], true, "meetings")
  }

  // Local-only commands (no network): hide/restore a meeting, clear session, unlink calendar.
  property string localAction: ""
  property string localSummary: ""
  function runLocal(args, action, summary) {
    if (localProc.running) return
    root.localAction = action
    root.localSummary = summary || ""
    localProc.command = [root.cli].concat(args)
    localProc.running = true
  }

  function finishLocal(output) {
    var result = {}
    try { result = JSON.parse(String(output).trim().split("\n").pop() || "{}") }
    catch (e) { result = { ok: false, error: "Unexpected output from timur-bar" } }
    stateFile.reload()
    if (!result.ok) { showMessage("Couldn't do that: " + (result.error || "timur-bar failed"), "error"); return }
    var action = root.localAction
    if (action === "dismiss") showMessage("Hidden “" + root.localSummary + "” — “hidden” next to MEETINGS brings it back", "")
    else if (action === "restore") showMessage("✓ “" + root.localSummary + "” is back in Meetings", "ok")
    else if (action === "calendar") {
      root.meetingPicks = ({})
      root.pickingFor = null
      showMessage("✓ Google Calendar unlinked", "ok")
    } else if (action === "session") showMessage("✓ Signed out — paste a session to connect again", "ok")
  }

  function dismissMeeting(m) {
    var picks = Object.assign({}, root.meetingPicks)
    delete picks[m.key]
    root.meetingPicks = picks
    runLocal(["dismiss-meeting", m.key], "dismiss", m.title)
  }

  function linkCalendar() {
    Quickshell.execDetached([root.cli, "set-calendar", "--window"])
    root.close()
  }

  function confirmed() {
    var action = root.confirmAction
    root.confirmAction = ""
    root.settingsOpen = false
    runLocal(["clear-" + action], action)
  }

  // ---- actions
  function refresh() {
    // Also fetch the day on screen: the background timer only keeps today and yesterday.
    if (runCli(["refresh", "--date", root.dayIso], false)) root.fetchedIso = root.dayIso
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

  // Log the same work again today (task, type, status, duration, description).
  function copyToToday(entry) {
    root.confirmDeleteId = ""
    root.pendingSummary = root.formatMinutes(entry.duration) + " · " + entry.task
    var fields = {
      date: root.todayIso, task: String(entry.taskId), type: entry.type || defaultType(),
      status: entry.status || "DONE", duration: entry.duration, description: entry.description || ""
    }
    runCli(["add-entry", JSON.stringify(fields)], true, "copy")
  }

  // Timer commands are local file updates in timur-bar; they don't share the save Process.
  property string timerAction: ""
  function runTimer(args) {
    if (timerProc.running) return
    root.timerAction = args[0]
    timerProc.command = [root.cli, "timer"].concat(args)
    timerProc.running = true
  }

  function startTimer() {
    if (root.selectedTaskId === "" || root.timer) return
    runTimer(["start", JSON.stringify({ task: root.selectedTaskId, label: root.selectedTaskLabel,
                                        type: root.entryType, description: root.description.trim() })])
  }

  function finishTimer(output) {
    var result = {}
    try { result = JSON.parse(String(output).trim().split("\n").pop() || "{}") }
    catch (e) { result = { ok: false, error: "Unexpected output from timur-bar" } }
    if (!result.ok) { showMessage(result.error || "Timer failed", "error"); timerFile.reload(); return }
    var t = result.timer
    if (root.timerAction === "stop") {
      // Fill the form (duration rounded to the minute) so it can be checked and saved.
      root.timer = null
      cancelEdit()
      root.dayOffset = 0
      root.selectedTaskId = String(t.task)
      root.entryType = t.type || defaultType()
      root.entryStatus = "DONE"
      root.durationText = formatMinutes(t.minutes)
      root.description = t.description || ""
      showMessage("■ Stopped at " + formatMinutes(t.minutes) + " — add a description and Save", "")
      descriptionField.forceActiveFocus()
    } else if (root.timerAction === "discard") {
      root.timer = null
      showMessage("Timer discarded", "")
    } else {
      root.timer = t
      if (root.timerAction === "start") {
        root.selectedTaskId = ""
        root.description = ""
        root.durationText = ""
        showMessage("▶ Timer started — it keeps running with the panel closed", "ok")
      }
    }
  }

  function addNote() {
    if (busy || noteText.trim() === "") return
    runCli(["add-note", root.dayIso, root.noteText.trim()], true, "note")
  }

  function openWebApp() {
    Quickshell.execDetached(["omarchy-launch-or-focus-webapp", "timur.dev.togglecorp.com", root.webApp])
    root.close()
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
    if (proc.running) return false
    root.pendingAction = action || ""
    if (isSave) {
      root.busy = true
      showMessage("Saving…", "")
    }
    proc.command = [root.cli].concat(args)
    proc.running = true
    return true
  }

  function finishCli(output) {
    var result = {}
    try { result = JSON.parse(String(output).trim().split("\n").pop() || "{}") }
    catch (e) { result = { ok: false, error: "Unexpected output from timur-bar" } }
    var action = root.pendingAction
    root.pendingAction = ""
    root.busy = false
    if (action === "") {  // refresh problems show in the header block
      if (result.ok) root.fetchedIso = ""
      return
    }
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
    } else if (action === "meetings") {
      showMessage("✓ Logged " + root.pendingSummary, "ok")
      Quickshell.execDetached(["notify-send", "--app-name=Timur", "--icon=appointment-new", "Timur", "Logged " + root.pendingSummary])
    } else if (action === "copy") {
      showMessage("✓ Copied " + root.pendingSummary + " to today", "ok")
      Quickshell.execDetached(["notify-send", "--app-name=Timur", "--icon=appointment-new", "Timur", "Copied " + root.pendingSummary + " to today"])
    } else if (action === "note") {
      showMessage("✓ Added to " + root.dayName.toLowerCase() + "'s journal", "ok")
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

  Process {
    id: timerProc
    stdout: StdioCollector {
      id: timerOut
      waitForEnd: true
    }
    onExited: root.finishTimer(timerOut.text)
  }

  Process {
    id: localProc
    stdout: StdioCollector {
      id: localOut
      waitForEnd: true
    }
    onExited: root.finishLocal(localOut.text)
  }

  FileView {
    id: timerFile
    path: Quickshell.env("HOME") + "/.cache/timur-bar/timer.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = null
      try { t = JSON.parse(text()) } catch (e) {}
      root.timer = t && t.started ? t : null
    }
    onLoadFailed: root.timer = null
  }

  // Ticks the clock on the bar and in the panel while the timer runs.
  Timer {
    interval: 1000
    running: !!root.timer && !root.timerPaused
    repeat: true
    onTriggered: root.now = new Date()
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
      if (root.hasData && !root.dayLoaded && root.fetchedIso !== root.dayIso) root.refresh()
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
      timerFile.reload()
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
          if (root.confirmAction !== "") root.confirmAction = ""
          else if (root.settingsOpen) root.settingsOpen = false
          else if (root.pickingFor) root.stopTaskSearch()
          else if (root.typeOpenKey !== "") root.typeOpenKey = ""
          else if (root.confirmDeleteId !== "") root.confirmDeleteId = ""
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
            Button {
              anchors.left: heading.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              id: webButton
              text: "Web ↗"
              tooltipText: "Open Timur in the browser"
              foreground: root.bar.foreground
              onClicked: root.openWebApp()
            }
            Button {
              anchors.left: webButton.right
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: "⚙"
              tooltipText: "Settings: Google Calendar, clear session"
              foreground: root.settingsOpen ? Color.accent : Qt.darker(root.bar.foreground, 1.3)
              onClicked: { root.settingsOpen = !root.settingsOpen; root.confirmAction = "" }
            }
            Text {
              textFormat: Text.PlainText
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.hasData ? root.dayName + " " + root.formatMinutes(root.day.totalMinutes) : ""
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

          // ---- ⚙ settings: link or unlink Google Calendar, clear the session (asks first)
          Flow {
            visible: root.settingsOpen && root.confirmAction === ""
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: root.calendarLinked ? "Google Calendar…" : "Link Google Calendar…"
              tooltipText: root.calendarLinked ? "Link another calendar, or a new secret address" :
                "Show your meetings here to log them (opens a terminal to paste the calendar's secret iCal address)"
              bordered: true
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              onClicked: root.linkCalendar()
            }
            Button {
              visible: root.calendarLinked
              text: "Unlink Google Calendar…"
              bordered: true
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              onClicked: root.confirmAction = "calendar"
            }
            Button {
              visible: root.hasData || !root.needsSession
              text: "Clear Timur session…"
              bordered: true
              fontSize: Style.font.bodySmall
              foreground: Color.urgent
              onClicked: root.confirmAction = "session"
            }
          }

          Rectangle {
            visible: root.confirmAction !== ""
            width: parent.width
            height: Math.max(confirmText.implicitHeight, confirmButtons.implicitHeight) + Style.space(12)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.bar.foreground, Color.urgent)

            Text {
              id: confirmText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: confirmButtons.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              wrapMode: Text.WordWrap
              text: root.confirmAction === "session" ? "Sign out of Timur on this computer? Nothing changes in Timur."
                : "Unlink Google Calendar? Your calendar itself is untouched."
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Row {
              id: confirmButtons
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                text: "Cancel"
                bordered: true
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                onClicked: root.confirmAction = ""
              }
              Button {
                text: root.confirmAction === "session" ? "Clear session" : "Unlink"
                bordered: true
                fontSize: Style.font.bodySmall
                foreground: Color.urgent
                onClicked: root.confirmed()
              }
            }
          }

          // ---- Week: total vs target, a button per day that opens it
          Item {
            visible: root.hasData && root.weekDays.length > 0
            width: parent.width
            height: weekRow.implicitHeight

            SectionLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "WEEK " + root.formatMinutes(root.weekMinutes) + " / " + root.weekTarget + "h"
              color: root.weekMinutes >= root.weekTarget * 60 ? Color.accent : Qt.darker(root.bar.foreground, 1.5)
            }
            Row {
              id: weekRow
              anchors.right: parent.right
              spacing: Style.space(2)

              Repeater {
                model: root.weekDays

                Button {
                  required property var modelData
                  readonly property date weekDate: new Date(modelData.date + "T00:00")
                  readonly property int weekOffset: Math.round((weekDate - new Date(root.todayIso + "T00:00")) / 86400000)
                  text: Qt.formatDate(weekDate, "ddd").slice(0, 2) + " " + (modelData.minutes ? root.formatMinutes(modelData.minutes) : "–")
                  tooltipText: Qt.formatDate(weekDate, "dddd d MMMM")
                  fontSize: Style.font.bodySmall
                  foreground: weekOffset === root.dayOffset ? Color.accent : Qt.darker(root.bar.foreground, 1.3)
                  onClicked: root.dayOffset = weekOffset
                }
              }
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
              visible: !!root.timer
              width: parent.width
              height: timerButtons.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.bar.foreground, Color.accent)

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: timerButtons.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                text: root.timer ? root.timerText + "  ·  " + (root.timer.label || "?") : ""
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
              Row {
                id: timerButtons
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  text: root.timerPaused ? "▶ Resume" : "⏸ Pause"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  onClicked: root.runTimer([root.timerPaused ? "resume" : "pause"])
                }
                Button {
                  text: "■ Stop"
                  tooltipText: "Stop and fill in the duration"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  onClicked: root.runTimer(["stop"])
                }
                Button {
                  text: "✕"
                  tooltipText: "Discard the timer"
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  onClicked: root.runTimer(["discard"])
                }
              }
            }

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

            Rectangle {
              visible: !!root.pickingFor
              width: parent.width
              height: pickingBanner.implicitHeight + Style.space(8)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(root.bar.foreground, Color.accent)

              Text {
                id: pickingBanner
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: "Picking a task for: " + (root.pickingTitles || "nothing") + " — Enter picks, Esc cancels"
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
                anchors.right: root.editing ? cancelEditButton.left : (startTimerButton.visible ? startTimerButton.left : saveButton.left)
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
                id: startTimerButton
                visible: !root.editing && root.dayOffset === 0 && !root.timer
                anchors.right: saveButton.left
                anchors.rightMargin: Style.space(6)
                text: "▶ Start timer"
                tooltipText: "Time this task; the bar shows the clock while it runs"
                bordered: true
                enabled: !root.busy && root.selectedTaskId !== "" && root.entryType !== ""
                foreground: root.bar.foreground
                onClicked: root.startTimer()
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

            // ---- Meetings from Google Calendar that aren't logged yet
            Column {
              visible: root.calendarLinked && (root.visibleMeetings.length > 0 || root.hiddenMeetings.length > 0 || root.calendarError !== "")
              width: parent.width
              spacing: Style.space(4)

              Hairline {}

              Item {
                width: parent.width
                height: logMeetingsButton.implicitHeight

                SectionLabel {
                  id: meetingsLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.visibleMeetings.length ? "MEETINGS · " + root.visibleMeetings.length + " TO LOG" : "MEETINGS"
                }
                Button {
                  visible: root.hiddenMeetings.length > 0
                  anchors.left: meetingsLabel.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.hiddenMeetings.length + " hidden"
                  tooltipText: "Meetings you marked as not work — restore one from here"
                  fontSize: Style.font.bodySmall
                  foreground: root.showHidden ? Color.accent : Qt.darker(root.bar.foreground, 1.4)
                  onClicked: root.showHidden = !root.showHidden
                }
                Button {
                  id: logMeetingsButton
                  anchors.right: parent.right
                  text: root.logMeetingsLabel
                  tooltipText: root.meetingProblems.length ? "Show the first meeting that needs fixing" : "Log the ticked meetings as DONE entries"
                  bordered: true
                  enabled: !root.busy && root.chosenMeetings.length > 0
                  foreground: root.bar.foreground
                  onClicked: root.logMeetings()
                }
              }

              Item {
                visible: root.calendarError !== ""
                width: parent.width
                height: Math.max(calendarErrorText.implicitHeight, linkAgain.implicitHeight)

                Text {
                  id: calendarErrorText
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: linkAgain.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  wrapMode: Text.WordWrap
                  text: "Calendar: " + root.calendarError
                  color: Color.urgent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Button {
                  id: linkAgain
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Link again"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  onClicked: root.linkCalendar()
                }
              }

              Row {
                visible: root.visibleMeetings.length > 1
                spacing: Style.space(8)

                Button {
                  text: (root.allTicked ? "☑" : "☐") + " all"
                  tooltipText: "Tick or untick every meeting"
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  onClicked: root.tickAll(!root.allTicked)
                }
                Button {
                  visible: root.tickedWithoutTask > 0
                  text: "Choose task for " + root.tickedWithoutTask + " ticked…"
                  tooltipText: "Pick one task for every ticked meeting that has none"
                  bordered: true
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  onClicked: root.startTaskSearch("ticked")
                }
              }

              // One line per meeting:  ☑ 10:00 Standup  [30m] [MapSwipe › RN Upgrade] [Meet·I] ✕
              Flickable {
                id: meetingsFlick
                readonly property real rowHeight: Style.space(30)
                width: parent.width
                height: Math.min(meetingsColumn.implicitHeight, root.meetingRows * rowHeight)
                contentWidth: width
                contentHeight: meetingsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                  id: meetingsColumn
                  width: meetingsFlick.width

                  Repeater {
                    model: root.visibleMeetings

                    Column {
                      id: meetingRow
                      required property var modelData
                      required property int index
                      readonly property var pick: root.pickFor(modelData)
                      // An earlier meeting still running when this one starts.
                      readonly property bool overlaps: root.visibleMeetings.slice(0, index).some(function(o) {
                        return new Date(o.end) > new Date(modelData.start)
                      })
                      readonly property string taskLabel: root.taskLabelFor(pick.task)
                      width: parent.width

                      Item {
                        width: parent.width
                        height: meetingsFlick.rowHeight

                        Rectangle {
                          anchors.fill: parent
                          radius: Style.cornerRadius
                          color: root.problemKey === meetingRow.modelData.key
                            ? Style.hoverFillFor(root.bar.foreground, Color.urgent) : "transparent"
                        }
                        Button {
                          id: tick
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          text: meetingRow.pick.on ? "☑" : "☐"
                          foreground: meetingRow.pick.on ? Color.accent : root.bar.foreground
                          onClicked: root.setPick(meetingRow.modelData, { on: !meetingRow.pick.on })
                        }
                        Text {
                          id: meetingTime
                          anchors.left: tick.right
                          anchors.leftMargin: Style.space(2)
                          anchors.verticalCenter: parent.verticalCenter
                          text: meetingRow.modelData.start.slice(11, 16)
                          color: meetingRow.overlaps ? Color.urgent : Qt.darker(root.bar.foreground, 1.4)
                          font.family: root.bar.fontFamily
                          font.pixelSize: Style.font.body
                        }
                        Text {
                          textFormat: Text.PlainText
                          anchors.left: meetingTime.right
                          anchors.leftMargin: Style.space(6)
                          anchors.right: meetingControls.left
                          anchors.rightMargin: Style.space(6)
                          anchors.verticalCenter: parent.verticalCenter
                          elide: Text.ElideRight
                          text: meetingRow.modelData.title
                          color: root.bar.foreground
                          font.family: root.bar.fontFamily
                          font.pixelSize: Style.font.body
                        }
                        Row {
                          id: meetingControls
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(4)

                          TextField {
                            width: Style.space(48)
                            foreground: root.bar.foreground
                            font.family: root.bar.fontFamily
                            text: meetingRow.pick.duration
                            onTextEdited: root.setPick(meetingRow.modelData, { duration: text })
                          }
                          Button {
                            text: meetingRow.taskLabel ? root.shortTask(meetingRow.taskLabel) : "Choose task…"
                            tooltipText: meetingRow.taskLabel ? meetingRow.taskLabel + "\nClick to change" : "Click to pick a task"
                            bordered: true
                            fontSize: Style.font.bodySmall
                            foreground: meetingRow.taskLabel ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4)
                            onClicked: root.startTaskSearch([meetingRow.modelData.key])
                          }
                          Button {
                            text: root.shortType(meetingRow.pick.type)
                            tooltipText: "Type — click to change"
                            bordered: true
                            fontSize: Style.font.bodySmall
                            foreground: Qt.darker(root.bar.foreground, 1.3)
                            onClicked: root.typeOpenKey = root.typeOpenKey === meetingRow.modelData.key ? "" : meetingRow.modelData.key
                          }
                          Button {
                            text: "✕"
                            tooltipText: "Not work — hide it (restore it from “hidden” next to MEETINGS)"
                            fontSize: Style.font.bodySmall
                            foreground: Qt.darker(root.bar.foreground, 1.3)
                            onClicked: root.dismissMeeting(meetingRow.modelData)
                          }
                        }
                      }

                      // The type choices, under the meeting whose type button was clicked.
                      Flow {
                        visible: root.typeOpenKey === meetingRow.modelData.key
                        width: parent.width
                        spacing: Style.space(4)
                        bottomPadding: Style.space(4)

                        Repeater {
                          model: root.data.types || []

                          Button {
                            required property var modelData
                            text: modelData.label
                            fontSize: Style.font.bodySmall
                            bordered: modelData.key === meetingRow.pick.type
                            foreground: modelData.key === meetingRow.pick.type ? Color.accent : root.bar.foreground
                            onClicked: {
                              root.setPick(meetingRow.modelData, { type: modelData.key })
                              root.typeOpenKey = ""
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Meetings marked as not work, with ↶ Restore.
              Rectangle {
                visible: root.showHidden && root.hiddenMeetings.length > 0
                width: parent.width
                height: hiddenColumn.implicitHeight + Style.space(8)
                radius: Style.cornerRadius
                color: Style.hoverFillFor(root.bar.foreground, Color.accent)

                Column {
                  id: hiddenColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  SectionLabel { text: "NOT WORK — HIDDEN" }

                  Repeater {
                    model: root.hiddenMeetings

                    Item {
                      required property var modelData
                      width: parent.width
                      height: restoreButton.implicitHeight

                      Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.right: restoreButton.left
                        anchors.rightMargin: Style.space(8)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: modelData.start.slice(11, 16) + "  " + modelData.title
                        color: Qt.darker(root.bar.foreground, 1.4)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                      }
                      Button {
                        id: restoreButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "↶ Restore"
                        tooltipText: "Offer this meeting again"
                        fontSize: Style.font.bodySmall
                        foreground: Color.accent
                        onClicked: root.runLocal(["restore-meeting", modelData.key], "restore", modelData.title)
                      }
                    }
                  }
                }
              }
            }

            Hairline {}

            Item {
              width: parent.width
              height: loggedLabel.implicitHeight
              SectionLabel { id: loggedLabel; text: "LOGGED " + root.dayName.toUpperCase() }
              SectionLabel { anchors.right: parent.right; text: root.formatMinutes(root.day.totalMinutes) }
            }

            Flickable {
              id: entriesFlick
              readonly property int count: (root.day.entries || []).length
              width: parent.width
              height: count ? Math.min(entriesColumn.implicitHeight, root.entryRows * entriesColumn.implicitHeight / count) : 0
              contentWidth: width
              contentHeight: entriesColumn.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentHeight > height

              Column {
                id: entriesColumn
                width: entriesFlick.width
                // Meetings logged from the calendar have a start time; show the column when any entry does.
                readonly property bool timed: (root.day.entries || []).some(function(e) { return !!e.startTime })

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
                      id: rowStart
                      visible: entriesColumn.timed
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      width: entriesColumn.timed ? Style.space(40) : 0
                      text: (entryRow.modelData.startTime || "").slice(0, 5)
                      color: Qt.darker(root.bar.foreground, 1.4)
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      id: rowDuration
                      anchors.left: rowStart.right
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
                        visible: !entryRow.confirming && root.dayOffset !== 0 && !!entryRow.modelData.taskId
                        text: "→ Today"
                        tooltipText: "Copy this entry to today"
                        fontSize: Style.font.bodySmall
                        foreground: root.bar.foreground
                        onClicked: root.copyToToday(entryRow.modelData)
                      }
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
              }
            }

            SectionLabel {
              visible: (root.day.entries || []).length === 0
              text: root.dayLoaded ? "Nothing logged yet" : "Loading…"
              font.italic: true
              font.letterSpacing: 0
            }
          }

          // ================= Journal tab
          Column {
            visible: root.hasData && root.tab === "journal"
            width: parent.width
            spacing: Style.space(8)

            SectionLabel { text: "ADD TO " + root.dayName.toUpperCase() + "'S JOURNAL" }

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

            SectionLabel { text: root.dayName.toUpperCase() + "'S JOURNAL" }

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
