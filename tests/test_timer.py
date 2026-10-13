"""Checks the shared ▶ timer (timur-bar timer …):  python3 tests/test_timer.py"""
import json
import os
import subprocess
import tempfile
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

CLI = str(Path(__file__).resolve().parent.parent / "bin" / "timur-bar")
spec = spec_from_loader("timur_bar", SourceFileLoader("timur_bar", CLI))
bar = module_from_spec(spec)
spec.loader.exec_module(bar)

# 100 s since start, 30 s of it paused before, paused again at 90 s
assert bar.timer_seconds({"started": 0, "pausedSeconds": 30}, now=100) == 70
assert bar.timer_seconds({"started": 0, "pausedSeconds": 30, "pausedAt": 90}, now=1000) == 60

with tempfile.TemporaryDirectory() as home:
    def timer(*args):
        out = subprocess.run([CLI, "timer", *args], capture_output=True, text=True, env={**os.environ, "HOME": home})
        return json.loads(out.stdout)

    assert timer("stop")["ok"] is False  # nothing running
    assert timer("start", '{"task": 7, "label": "EOC", "type": "DEVELOPMENT"}')["timer"]["task"] == "7"
    assert timer("start", '{"task": 8}')["ok"] is False  # one at a time
    assert timer("pause")["timer"]["pausedAt"]
    assert timer("resume")["timer"]["pausedAt"] is None
    stopped = timer("stop")["timer"]
    assert stopped["minutes"] == 1 and stopped["label"] == "EOC"  # rounds up to at least a minute
    assert not (Path(home) / ".cache/timur-bar/timer.json").exists()
print("timer ok")
