"""Checks timur-menu's one-line quick log parser:  python3 tests/test_quick_log.py"""
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

path = str(Path(__file__).resolve().parent.parent / "i3" / "timur-menu")
spec = spec_from_loader("timur_menu", SourceFileLoader("timur_menu", path))
menu = module_from_spec(spec)
spec.loader.exec_module(menu)

parse = menu.parse_quick
assert parse("eoc 1.5 fixed login bug") == (["eoc"], 90, "DONE", "fixed login bug")
assert parse("EOC upgrade 45m") == (["eoc", "upgrade"], 45, "DONE", "")
assert parse("hdr 2026 1h30 review") == (["hdr", "2026"], 90, "DONE", "review")  # 2026 isn't a time (> 24h)
assert parse("helix todo write tests") == (["helix"], 0, "TODO", "write tests")
assert parse("helix Doing") == (["helix"], 0, "DOING", "")
assert parse("1.5 no task words") is None
assert parse("helix only words") is None

tasks = [{"id": 1, "label": "EOC › Upgrade"}, {"id": 2, "label": "Helix › HDR 2026"}, {"id": 3, "label": "EOC › Support"}]
assert [t["id"] for t in menu.match_tasks(["eoc"], tasks, ["3"])] == [3, 1]  # recent first
assert [t["id"] for t in menu.match_tasks(["eoc", "upg"], tasks, [])] == [1]
assert menu.match_tasks(["nope"], tasks, []) == []
print("quick log parser ok")
