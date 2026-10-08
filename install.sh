#!/bin/bash
# Install timur-bar for Omarchy (bar plugin) or i3 (polybar/i3blocks + rofi).
#
#   ./install.sh               auto-detect Omarchy or i3
#   ./install.sh --omarchy     force the Omarchy front end
#   ./install.sh --i3          force the i3 front end
#   ./install.sh --no-bindings don't add keybindings
#
# Safe to run again: links are refreshed and config blocks are only added once
# (between "timur-bar" marker comments, which uninstall.sh removes).
set -euo pipefail

NAME=timur-bar
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' "$REPO/manifest.json" | head -1)"
BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"

frontend=""
bindings=1
for arg in "$@"; do
  case "$arg" in
    --omarchy) frontend=omarchy ;;
    --i3) frontend=i3 ;;
    --no-bindings) bindings=0 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z $frontend ]]; then
  if command -v omarchy-shell >/dev/null 2>&1; then frontend=omarchy
  elif [[ ${XDG_CURRENT_DESKTOP:-} == *i3* ]] || pgrep -x i3 >/dev/null 2>&1 || [[ -f $HOME/.config/i3/config ]]; then frontend=i3
  else
    echo "Couldn't detect Omarchy or i3 — pass --omarchy or --i3." >&2
    exit 1
  fi
fi
echo "==> Installing $NAME ($frontend front end) from $REPO"

link() {  # link SOURCE TARGET — replace an existing link, back up a real file
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst && ! -L $dst ]]; then
    mv "$dst" "$dst.bak.$(date +%s)"
    echo "    backed up existing $dst"
  fi
  ln -sfn "$src" "$dst"
  echo "    $dst -> $src"
}

add_block() {  # add_block SNIPPET TARGET — append once, between markers
  local snippet=$1 target=$2
  mkdir -p "$(dirname "$target")"
  touch "$target"
  if grep -q ">>> $NAME >>>" "$target"; then
    echo "    keybindings already in $target"
  else
    printf '\n' >>"$target"
    cat "$snippet" >>"$target"
    echo "    added keybindings to $target"
  fi
}

chmod +x "$REPO/bin/"* "$REPO/i3/timur-menu" "$REPO/i3/i3blocks-timur"

echo "--> Script"
link "$REPO/bin/timur-bar" "$BIN/timur-bar"

echo "--> Background refresh (systemd user timer)"
for unit in "$REPO"/systemd/*; do link "$unit" "$UNITS/$(basename "$unit")"; done
systemctl --user daemon-reload
systemctl --user enable --now timur-bar-refresh.timer >/dev/null
echo "    timur-bar-refresh.timer enabled"

if [[ $frontend == omarchy ]]; then
  echo "--> Omarchy bar plugin ($PLUGIN_ID)"
  plugin_dir="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
  if [[ "$(readlink -f "$plugin_dir" 2>/dev/null)" == "$REPO" ]]; then
    echo "    plugin folder is this repo"
  elif [[ -e $plugin_dir ]]; then
    echo "    $plugin_dir already exists and is not this repo — move it away first" >&2
    exit 1
  else
    link "$REPO" "$plugin_dir"
  fi
  if ! jq -e --arg id "$PLUGIN_ID" '[.bar.layout[]?[]?.id] | index($id)' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
    omarchy plugin enable "$PLUGIN_ID" --section right >/dev/null && echo "    added to the bar (right side)"
  else
    echo "    already in the bar"
  fi
  if (( bindings )); then
    add_block "$REPO/omarchy/bindings.lua" "$HOME/.config/hypr/bindings.lua"
    hyprctl reload >/dev/null 2>&1 || true
  fi
else
  echo "--> i3 front end"
  link "$REPO/i3/timur-menu" "$BIN/timur-menu"
  link "$REPO/i3/i3blocks-timur" "$BIN/i3blocks-timur"
  (( bindings )) && add_block "$REPO/i3/i3.config" "$HOME/.config/i3/config"
  for dep in rofi notify-send; do
    command -v "$dep" >/dev/null 2>&1 || echo "    ! missing: $dep  (sudo pacman -S ${dep/notify-send/libnotify})"
  done
  pgrep -x dunst >/dev/null 2>&1 || echo "    ! no dunst running — notifications need a daemon (sudo pacman -S dunst)"
  cat <<EOF
    Add the bar module yourself (one of):
      polybar:  $REPO/i3/polybar.ini   → then add "timur" to modules-right
      i3blocks: $REPO/i3/i3blocks.conf
    Then reload i3 (\$mod+Shift+r).
EOF
fi

echo "--> Session"
if [[ -s $HOME/.config/timur-bar/session ]]; then
  echo "    session file exists — run 'timur-bar set-session' if it has expired"
elif [[ -t 0 ]]; then
  "$BIN/timur-bar" set-session || true
else
  echo "    run 'timur-bar set-session' to connect"
fi
echo "==> Done"
