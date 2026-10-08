#!/bin/bash
# Remove what install.sh set up. Keeps your session (~/.config/timur-bar) unless --purge.
set -euo pipefail

NAME=timur-bar
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' "$REPO/manifest.json" | head -1)"
purge=0
[[ ${1:-} == --purge ]] && purge=1

unlink_if_ours() {  # only remove links that point into this repo
  local dst=$1
  if [[ -L $dst && "$(readlink -f "$dst")" == "$REPO"* ]]; then
    rm "$dst" && echo "    removed $dst"
  fi
}

remove_block() {
  local target=$1
  [[ -f $target ]] && grep -q ">>> $NAME >>>" "$target" || return 0
  sed -i "/>>> $NAME >>>/,/<<< $NAME <<</d" "$target"
  echo "    removed keybindings from $target"
}

echo "==> Uninstalling $NAME"
systemctl --user disable --now timur-bar-refresh.timer >/dev/null 2>&1 || true
for unit in "$REPO"/systemd/*; do unlink_if_ours "$HOME/.config/systemd/user/$(basename "$unit")"; done
systemctl --user daemon-reload

for f in timur-bar timur-panel timur-menu i3blocks-timur; do unlink_if_ours "$HOME/.local/bin/$f"; done

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  unlink_if_ours "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
fi
remove_block "$HOME/.config/hypr/bindings.lua"
remove_block "$HOME/.config/i3/config"

if (( purge )); then
  rm -rf "$HOME/.config/timur-bar" "$HOME/.cache/timur-bar"
  echo "    removed session and cache"
else
  echo "    kept ~/.config/timur-bar (session) — use --purge to remove it"
fi
echo "==> Done. Remove the bar module from your polybar/i3blocks config if you added one."
