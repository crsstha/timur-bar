#!/usr/bin/env python3
"""Add or remove timur-bar's GNOME keyboard shortcuts (Settings → Keyboard → Custom Shortcuts).

  keybindings.py add      Super+Alt+T log time · Super+Alt+J journal note · Super+Alt+Q quick log (needs rofi)
  keybindings.py remove   take them out again (used by uninstall.sh)

Only touches entries under …/custom-keybindings/timur-bar-*/, so your own shortcuts are kept.
"""

import ast
import shutil
import subprocess
import sys
from pathlib import Path

SCHEMA = "org.gnome.settings-daemon.plugins.media-keys"
ITEM_SCHEMA = SCHEMA + ".custom-keybinding"
BASE = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
BIN = Path.home() / ".local/bin"
BINDINGS = {  # path suffix: (name, command, accelerator)
    "timur-bar-panel": ("Timur: log time", f"{BIN}/timur-panel", "<Super><Alt>t"),
    "timur-bar-journal": ("Timur: journal note", f"{BIN}/timur-panel journal", "<Super><Alt>j"),
    "timur-bar-quick": ("Timur: quick log", f"{BIN}/timur-menu quick", "<Super><Alt>q"),
}


def gsettings(*args):
    return subprocess.run(["gsettings", *args], check=True, capture_output=True, text=True).stdout.strip()


def current_paths():
    value = gsettings("get", SCHEMA, "custom-keybindings")
    return list(ast.literal_eval(value.removeprefix("@as "))) if value else []


def main(argv):
    action = argv[1] if len(argv) > 1 else ""
    if action not in ("add", "remove"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    paths = [p for p in current_paths() if not p.startswith(BASE + "timur-bar-")]
    if action == "add":
        for key, (name, command, accel) in BINDINGS.items():
            if key == "timur-bar-quick" and not shutil.which("rofi"):
                continue
            path = f"{BASE}{key}/"
            for field, value in (("name", name), ("command", command), ("binding", accel)):
                gsettings("set", f"{ITEM_SCHEMA}:{path}", field, value)
            paths.append(path)
            print(f"    {accel.replace('<', '').replace('>', '+')}: {name}")
    else:
        for key in BINDINGS:
            subprocess.run(["gsettings", "reset-recursively", f"{ITEM_SCHEMA}:{BASE}{key}/"], capture_output=True)
    gsettings("set", SCHEMA, "custom-keybindings", str(paths))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
