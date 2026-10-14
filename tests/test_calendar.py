"""Checks the Google Calendar reader (meetings offered as entries):  python3 tests/test_calendar.py"""
import json
import os
import tempfile
import time
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

os.environ["TZ"] = "Asia/Kathmandu"  # +05:45, so time zone mistakes show
time.tzset()

CLI = str(Path(__file__).resolve().parent.parent / "bin" / "timur-bar")
spec = spec_from_loader("timur_bar", SourceFileLoader("timur_bar", CLI))
bar = module_from_spec(spec)
spec.loader.exec_module(bar)

URL = "https://calendar.google.com/calendar/ical/me%40org.example/private-abc123/basic.ics"
OWNER = bar.calendar_owner(URL)
assert OWNER == "me@org.example"

# Shaped like Google's export: CRLF, folded lines, VALARMs, overrides after the series.
ICS = "\r\n".join("""BEGIN:VCALENDAR
X-WR-CALNAME:me@org.example
BEGIN:VEVENT
DTSTART;TZID=Asia/Kathmandu:20260902T100000
DTEND;TZID=Asia/Kathmandu:20260902T103000
RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=MO,TU,WE,TH,FR
EXDATE;TZID=Asia/Kathmandu:20261012T100000
UID:standup@google.com
SUMMARY:Standup
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:This is an event reminder
SUMMARY:Alarm notification
END:VALARM
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Kathmandu:20261013T110000
DTEND;TZID=Asia/Kathmandu:20261013T113000
RECURRENCE-ID;TZID=Asia/Kathmandu:20261013T100000
UID:standup@google.com
SUMMARY:Standup (moved)
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Kathmandu:20261014T100000
DTEND;TZID=Asia/Kathmandu:20261014T103000
RECURRENCE-ID;TZID=Asia/Kathmandu:20261014T100000
STATUS:CANCELLED
UID:standup@google.com
SUMMARY:Standup
END:VEVENT
BEGIN:VEVENT
DTSTART:20260928T080000Z
DTEND:20260928T090000Z
RRULE:FREQ=WEEKLY;WKST=SU;INTERVAL=2;BYDAY=MO
UID:biweekly@google.com
SUMMARY:Biweekly sync
END:VEVENT
BEGIN:VEVENT
DTSTART:20260113T140000
DTEND:20260113T150000
RRULE:FREQ=MONTHLY;BYDAY=2TU
UID:monthly@google.com
SUMMARY:Second-Tuesday review
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Kathmandu:20260130T160000
DTEND;TZID=Asia/Kathmandu:20260130T170000
RRULE:FREQ=MONTHLY;BYDAY=-1FR
UID:lastfriday@google.com
SUMMARY:Last-Friday demo
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Kathmandu:20261011T080000
DTEND;TZID=Asia/Kathmandu:20261011T081500
RRULE:FREQ=DAILY;COUNT=3
UID:count@google.com
SUMMARY:Three days
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Kathmandu:20261010T090000
DTEND;TZID=Asia/Kathmandu:20261010T091500
RRULE:FREQ=DAILY;UNTIL=20261012T235959Z
UID:until@google.com
SUMMARY:Until the 12th
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261013
DTEND;VALUE=DATE:20261014
UID:allday@google.com
SUMMARY:Holiday
END:VEVENT
BEGIN:VEVENT
DTSTART:20261013T060000Z
DTEND:20261013T070000Z
UID:declined@google.com
SUMMARY:Vendor pitch
ATTENDEE;CN=me@org.example;PARTSTAT=DECLINED:mailto:me@org.example
ATTENDEE;CN=Boss;PARTSTAT=ACCEPTED:mailto:boss@org.example
END:VEVENT
BEGIN:VEVENT
DTSTART:20261013T070000Z
DTEND:20261013T073000Z
UID:tentative@google.com
SUMMARY:Maybe
ATTENDEE;CN="Me: myself";PARTSTAT=TENTATIVE:mailto:me@org.example
END:VEVENT
BEGIN:VEVENT
DTSTART:20261013T000000Z
DTEND:20261013T010000Z
RRULE:FREQ=WEEKLY;BYSETPOS=1;BYDAY=MO
UID:odd@google.com
SUMMARY:Odd rule
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=Asia/Kathmandu:20261013T150000
DURATION:PT45M
UID:single@google.com
SUMMARY:Design sync\\, part 2 with a title long enough that Google folds
  the line
END:VEVENT
BEGIN:VEVENT
DTSTART;TZID=America/New_York:20261012T090000
DTEND;TZID=America/New_York:20261012T093000
UID:ny@google.com
SUMMARY:NY call
END:VEVENT
END:VCALENDAR""".splitlines()) + "\r\n"

DAYS = ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-30"]
found, skipped = bar.calendar_meetings(ICS, OWNER, DAYS)


def day(d):
    return [(m["start"][11:16], m["title"], m["minutes"]) for m in found.get(d, [])]


assert skipped == ["Odd rule"]
assert sorted(day("2026-10-12")) == [         # Standup is EXDATEd
    ("08:00", "Three days", 15),               # from the 11th, COUNT=3
    ("09:00", "Until the 12th", 15),           # UNTIL in UTC still covers the 12th
    ("13:45", "Biweekly sync", 60),            # 08:00Z, every other Monday (WKST=SU)
    ("18:45", "NY call", 30),                  # 09:00 New York (EDT) in Kathmandu
]
assert sorted(day("2026-10-13")) == sorted([
    ("08:00", "Three days", 15),               # third and last
    ("11:00", "Standup (moved)", 30),          # override replaces the 10:00 occurrence
    ("12:45", "Maybe", 30),                    # tentative is kept; declined Vendor pitch and the Holiday aren't
    ("14:00", "Second-Tuesday review", 60),    # floating time = local
    ("15:00", "Design sync, part 2 with a title long enough that Google folds the line", 45),
])
assert day("2026-10-14") == []                 # standup cancelled, Three days over, no Until
assert sorted(day("2026-10-30")) == [("10:00", "Standup", 30), ("16:00", "Last-Friday demo", 60)]
assert all(m["title"] != "Alarm notification" for ms in found.values() for m in ms)

# Weekly series that starts mid-week (Wed) still has its first Monday.
assert [d.date().isoformat() for d in bar.rrule_starts(
    bar.dt.datetime(2026, 9, 2, 10), {"FREQ": "WEEKLY", "BYDAY": "MO,WE"}, bar.dt.date(2026, 9, 8))] \
    == ["2026-09-02", "2026-09-07"]

# Already logged (same start minute) or dismissed meetings aren't offered.
meetings = found["2026-10-13"]
standup = next(m for m in meetings if m["title"] == "Standup (moved)")
review = next(m for m in meetings if m["title"] == "Second-Tuesday review")
left = bar.unlogged(meetings, [{"startTime": "11:00:00"}, {"startTime": None}], {review["key"]})
assert standup not in left and review not in left and len(left) == len(meetings) - 2

# Task/type learned for the series first, then the title; tasks no longer active are ignored.
learned = {"uid:standup@google.com": {"task": "7", "type": "INTERNAL_MEETING"},
           "title:maybe": {"task": "9", "type": "REVIEW"}}
assert bar.suggestion(standup, learned, {"7"}) == {"task": "7", "type": "INTERNAL_MEETING"}
assert bar.suggestion(next(m for m in meetings if m["title"] == "Maybe"), learned, {"7"}) == {}
assert bar.suggestion(next(m for m in meetings if m["title"] == "Maybe"), learned, {"9"})["type"] == "REVIEW"

with tempfile.TemporaryDirectory() as home:
    bar.CALENDAR = Path(home) / "calendar"
    bar.CALENDAR_STATE = Path(home) / "calendar.json"
    bar.STATE = Path(home) / "state.json"
    bar.CACHE = Path(home)

    # No calendar file: feature off, nothing fetched.
    days_state = {d: {"entries": []} for d in DAYS}
    assert bar.add_meetings(days_state, set(), {}) == (False, "")
    assert "meetings" not in days_state["2026-10-13"]

    bar.CALENDAR.write_text(f"url={URL}\n")
    bar.fetch_ics = lambda url: ICS
    days_state = {d: {"entries": []} for d in DAYS}
    assert bar.add_meetings(days_state, {"7"}, {}) == (True, "")
    assert len(days_state["2026-10-13"]["meetings"]) == 5
    assert json.loads(bar.CALENDAR_STATE.read_text())["skipped"] == ["Odd rule"]
    assert "Odd rule" in (Path(home) / "log").read_text()  # noted once for troubleshooting

    # A second calendar holding the same (moved) standup doesn't double it, but adds its own events.
    team_ics = ICS[:ICS.index("BEGIN:VEVENT\r\nDTSTART;TZID=Asia/Kathmandu:20261014")] + \
        "BEGIN:VEVENT\r\nDTSTART:20261013T100000Z\r\nDTEND:20261013T110000Z\r\nUID:team@google.com\r\n" \
        "SUMMARY:Team retro\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    bar.fetch_ics = lambda url: ICS if "me%40" in url else team_ics
    bar.CALENDAR.write_text(f"url={URL}\nurl={URL.replace('me%40', 'team%40')}\n")
    days_state = {d: {"entries": []} for d in DAYS}
    bar.add_meetings(days_state, set(), {})
    assert [m["title"] for m in days_state["2026-10-13"]["meetings"]].count("Standup (moved)") == 1
    assert [m["start"][11:16] for m in days_state["2026-10-13"]["meetings"]][-1] == "15:45"  # Team retro, sorted

    # Calendar down: keep the last meetings, report the error, never raise.
    def down(url):
        raise bar.TimurError("Can't reach Google Calendar", "network")
    bar.fetch_ics = down
    previous = {"days": days_state}
    days_state = {d: {"entries": [{"startTime": "08:00:00"}]} for d in DAYS}
    assert bar.add_meetings(days_state, set(), previous) == (True, "Can't reach Google Calendar")
    assert [m["start"][11:16] for m in days_state["2026-10-13"]["meetings"]] == ["11:00", "12:45", "14:00", "15:00", "15:45"]

    # log-meetings learns task/type; dismiss-meeting drops its event and title from every day in state.json at once.
    added = []
    bar.add_entry = lambda payload: added.append(json.loads(payload)) or {"ok": True}
    bar.log_meetings(json.dumps([{"task": 7, "type": "INTERNAL_MEETING", "duration": 30, "date": "2026-10-13",
                                  "startTime": "11:00", "uid": "standup@google.com", "title": "Standup (moved)"}]))
    learned = json.loads(bar.CALENDAR_STATE.read_text())["learned"]
    assert learned["uid:standup@google.com"] == learned["title:standup (moved)"] == {"task": "7", "type": "INTERNAL_MEETING"}
    assert added[0][0]["startTime"] == "11:00"
    bar.write_json(bar.STATE, {"days": days_state})
    key = days_state["2026-10-13"]["meetings"][0]["key"]
    assert bar.dismiss_meeting(key) == {"ok": True}
    day_view = json.loads(bar.STATE.read_text())["days"]["2026-10-13"]
    assert key not in [m["key"] for m in day_view["meetings"]] and key in [m["key"] for m in day_view["hidden"]]
    uid, title = bar.series_uid(key), day_view["hidden"][0]["title"]
    assert json.loads(bar.CALENDAR_STATE.read_text())["dismissedEvents"] == [f"uid:{uid}", f"title:{title.casefold()}"]
    # Another event with the same title (any case) is hidden too; other titles aren't.
    saved = json.loads(bar.CALENDAR_STATE.read_text())
    assert bar.is_dismissed({"key": "other@google.com|2026-10-20T13:00", "uid": "other@google.com",
                             "title": title.upper()}, saved)
    assert not bar.is_dismissed({"key": "other@google.com|2026-10-20T13:00", "uid": "other@google.com",
                                 "title": "Something else"}, saved)

    def offered(days):
        return {d: [m["title"] for m in v["meetings"] if m["uid"] == uid] for d, v in days.items() if v.get("meetings")}

    def hidden(days):
        return {d: [m["title"] for m in v["hidden"] if m["uid"] == uid] for d, v in days.items() if v.get("hidden")}

    # A refresh hides that event on every day it's on (not dropped), and restore-meeting brings it all back.
    bar.fetch_ics = lambda url: ICS
    days_state = {d: {"entries": []} for d in DAYS}
    bar.add_meetings(days_state, set(), {})
    assert not any(offered(days_state).values())
    assert len([d for d, titles in hidden(days_state).items() if titles]) > 1  # a repeating event: several days
    bar.write_json(bar.STATE, {"days": days_state})
    assert bar.restore_meeting(key) == {"ok": True}
    days_view = json.loads(bar.STATE.read_text())["days"]
    assert not any(hidden(days_view).values()) and len([d for d, t in offered(days_view).items() if t]) > 1
    day_view = days_view["2026-10-13"]
    assert key in [m["key"] for m in day_view["meetings"]] and not day_view["hidden"]
    assert [m["start"] for m in day_view["meetings"]] == sorted(m["start"] for m in day_view["meetings"])
    assert json.loads(bar.CALENDAR_STATE.read_text())["dismissedEvents"] == []

    # Meetings hidden one day at a time before this still stay hidden, and restore clears them too.
    bar.write_json(bar.CALENDAR_STATE, {"dismissed": [key]})
    days_state = {d: {"entries": []} for d in DAYS}
    bar.add_meetings(days_state, set(), {})
    assert key in [m["key"] for m in days_state["2026-10-13"]["hidden"]]
    bar.restore_meeting(key)
    assert json.loads(bar.CALENDAR_STATE.read_text())["dismissed"] == []
print("calendar ok")
