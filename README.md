# timur-bar

Log time and journal notes to [Timur](https://timur.dev.togglecorp.com/) (Togglecorp's timesheet) from your desktop bar, without opening the web app.

- **Omarchy:** a bar plugin with a panel: task search, hours, description, today's entries with **Edit / Delete**, and the journal.
- **i3:** a polybar or i3blocks module plus **rofi** menus for the same actions.

```
 󰔟 5h20      logged today
 󰔟 1h10      dimmed: after 17:00 with under 2h logged
 󰔟 5h20 •    session expires within 3 days
 󰔟 !         not connected / session expired
```

## How it works

```
bin/timur-bar  ── the only part that talks to Timur (GraphQL + your session cookie)
   │  refresh every 5 min (systemd user timer) → ~/.cache/timur-bar/state.json
   ▼
Omarchy: Panel.qml / BarWidget.qml      i3: timur-bar bar  +  i3/timur-menu (rofi)
```

Both front ends read the same cached state and call the same script to save, so they behave the same.

## Requirements

- Python 3 (standard library only), systemd user session, `notify-send`
- **Omarchy:** nothing else
- **i3:** `rofi`, a notification daemon (`dunst`), and `polybar` or `i3blocks`
- A Timur account you can log into in the browser

## Install on Omarchy

**1. Get the code** (either way works):

```bash
# a) git clone — keep it wherever you like
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar
cd ~/Projects/timur-bar

# b) Omarchy's plugin manager — clones into ~/.config/omarchy/plugins/crsstha.timur
#    and lets you update later with `omarchy plugin update`
omarchy plugin add https://github.com/crsstha/timur-bar.git --enable
cd ~/.config/omarchy/plugins/crsstha.timur
```

**2. Run the installer:**

```bash
./install.sh
```

It:
- links `bin/timur-bar` to `~/.local/bin`;
- starts the 5-minute refresh timer;
- puts the widget on the right of the bar;
- adds `Super+Alt+T` / `Super+Alt+J` to `~/.config/hypr/bindings.lua`.

**3. Connect your Timur session.** The installer asks for this on first run; see [Connect your session](#connect-your-session).

**4. Check it works:**
- The bar shows `󰔟 0m` (or your logged time). If you don't see it, run `omarchy restart shell`.
- `Super+Alt+T` opens the panel.
- `timur-bar refresh` prints `{"ok": true}`.

## Install on i3 (Arch Linux)

On i3 the bar module opens **rofi menus** for the same actions. The Omarchy panel (`Panel.qml`) needs Omarchy's Quickshell shell and does not run on i3.

**1. Install the dependencies:**

```bash
sudo pacman -S --needed git python rofi dunst libnotify xdg-utils alacritty ttf-nerd-fonts-symbols
sudo pacman -S --needed polybar      # or: i3blocks
```

`ttf-nerd-fonts-symbols` provides the `󰔟` icon. To use plain text instead, set `export TIMUR_BAR_ICON="T:"` in `~/.profile`.

**2. Get the code and run the installer:**

```bash
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar
cd ~/Projects/timur-bar
./install.sh --i3
```

It:
- links `timur-bar`, `timur-menu` and `i3blocks-timur` into `~/.local/bin`;
- starts the refresh timer;
- appends a marked block to `~/.config/i3/config`, with the keybindings (`Super+Alt+t/j/e`, written as `Mod4+Mod1` so they work whether `$mod` is Super or Alt) and an `import-environment` line so the timers can send notifications.

**3. Make sure notifications work.** If `dunst` isn't started anywhere yet, add this to `~/.config/i3/config`:

```
exec --no-startup-id dunst
```

**4. Add the module to your bar.** Choose **one**:

<details open><summary><b>polybar</b></summary>

1. Append the module to your polybar config:
   ```bash
   command cat ~/Projects/timur-bar/i3/polybar.ini >> ~/.config/polybar/config.ini
   ```
   `command cat` skips shell aliases. If `cat` is aliased to `bat`, the plain command can hang waiting on stdin and write what you type into the config.
2. In your `[bar/…]` section, add `timur` to a modules list, and make sure a font has the icon. Put it **last** in `modules-right` to have it in the top-right corner:
   ```ini
   modules-right = date timur
   font-1 = "Symbols Nerd Font:size=11"
   ```
3. Restart polybar, e.g. `polybar-msg cmd restart` or your launch script.

</details>

<details><summary><b>i3blocks</b></summary>

1. Append the block:
   ```bash
   mkdir -p ~/.config/i3blocks
   cat ~/Projects/timur-bar/i3/i3blocks.conf >> ~/.config/i3blocks/config
   ```
2. Make sure i3's bar uses i3blocks, in `~/.config/i3/config`:
   ```
   bar {
       status_command i3blocks
   }
   ```

</details>

**5. Reload i3** with `$mod+Shift+r`.

**6. Connect your Timur session.** The installer asks on first run, or run `timur-bar set-session`. See [Connect your session](#connect-your-session).

**7. Check it works:**
- `timur-bar bar` prints e.g. `󰔟 0m`.
- The bar shows the same text, and left-clicking it opens the rofi menu.
- `Super+Alt+t` asks for a task.

## Connect your session

Timur signs in with Google and has no API keys, so `timur-bar` reuses your browser session:

1. Log into the Timur web app → **F12** → **Application** → **Cookies** → `https://timur.dev.togglecorp.com`.
2. Run `timur-bar set-session`, or use **Paste session** in the panel or menu.
3. Paste the **Value** of each cookie:

   | Cookie | |
   |---|---|
   | `__Secure-timur-PROD-sessionid` | your login session |
   | `timur-PROD-csrftoken` | CSRF token |

It's saved to `~/.config/timur-bar/session` (`chmod 600`). Sessions last about a month, and the bar shows `•` three days before expiry. To renew, run `timur-bar set-session` again.

> ⚠ The session cookie is as good as your password for Timur. Never commit or share it.

## Update

```bash
cd ~/Projects/timur-bar && git pull     # or: omarchy plugin update crsstha.timur
./install.sh                             # safe to re-run; picks up new files
omarchy restart shell                    # Omarchy only, to reload the panel
```

**i3:** `install.sh` does not replace a keybinding block that is already in your i3 config. To pick up new keybindings, delete the lines between `# >>> timur-bar >>>` and `# <<< timur-bar <<<` in `~/.config/i3/config`, then run `./install.sh --i3` again.

## Usage

| | Omarchy | i3 |
|---|---|---|
| Log time | `Super+Alt+T` or left-click | `Super+Alt+t`, scroll up on the module, or left-click → *Log time* |
| Journal note | `Super+Alt+J` | `Super+Alt+j` |
| Edit / delete entries | hover an entry in *Logged today* | `Super+Alt+e` or menu → *Entries* |
| Refresh | middle-click | middle-click |
| Open Timur in the browser | right-click | right-click |
| Yesterday | *Yesterday* button | menu → *Switch to yesterday* |

**Duration is in hours:**

| Input | Saved |
|---|---|
| `1` | 1h |
| `1.5` | 1h30 |
| `0.25` | 15m |
| `1h30`, `1:30` | 1h30 |
| `45m` | 45 minutes (needs the `m`) |
| over 24h | rejected as a typo |

**Task list:** your recent tasks (last 7 days) come first. Type to search all active tasks.

**Journal:** each note is appended as `- HH:MM text`. The script re-reads the journal right before saving, because Timur replaces the whole text on save. Avoid editing the same day in the web app at the same moment.

## Commands

```bash
timur-bar refresh                         # fetch now
timur-bar set-session [--window]          # connect / refresh the session
timur-bar bar [--polybar|--i3blocks]      # bar text from cache (no network)
timur-bar add-entry '{"date":"2026-10-08","task":"117","type":"DEVELOPMENT","status":"DONE","duration":90,"description":"…"}'
timur-bar update-entry '{"clientId":"01…","description":"…"}'
timur-bar delete-entry <clientId> [date]
timur-bar add-note <date> "text"
tail -n 5 ~/.cache/timur-bar/log | jq .   # every save attempt and its result
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `󰔟 !` / "Not connected" | Session missing or expired → `timur-bar set-session` |
| Connected check says not logged in | Copy the **Value** of `__Secure-timur-PROD-sessionid`, not another row |
| "Something unexpected has occurred" | Server-side error. Check `~/.cache/timur-bar/log` for the request |
| "Invalid pk … does not exist" | That task is no longer active. Refresh and pick again |
| Omarchy panel shows old behaviour after editing | `omarchy restart shell` |
| i3: `Duplicate keybinding` for `timur-menu` on reload | Old block using `$mod+Mod1`, which is plain Alt when `$mod` is Alt. Replace it with the current `i3/i3.config` block (see [Update](#update)) |
| i3: no notifications from timers | Make sure the `import-environment` line from `i3/i3.config` is in your i3 config, and that `dunst` is running |
| i3: module shows nothing / clicks do nothing | Run `~/.local/bin/i3blocks-timur` or `timur-bar bar` in a terminal to see the error. Check the paths in your bar config |
| i3: icon shows as a box | Install `ttf-nerd-fonts-symbols` and add it as a polybar font, or set `TIMUR_BAR_ICON` |

## Notes for maintainers

- The GraphQL operations are the web app's own: `Me`, `Enums` (`allActiveTasks`), `MyTimeEntries`, `Note`, `UpdateNote` and `CudTimeEntry`.
- `CudTimeEntry` matches **updates and deletes by `clientId`**, limited to your own entries.
- New entries need a **ULID** `clientId`, because the column holds at most 26 characters.
- Cookie names come from `toggle-corp/timur-backend` `main/settings.py`.
- Timur's nightly job **moves TODO entries** from past days to today.

## Uninstall

```bash
~/Projects/timur-bar/uninstall.sh            # keeps your session
~/Projects/timur-bar/uninstall.sh --purge    # also removes session and cache
```

## License

MIT
