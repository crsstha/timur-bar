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

## Install

### Omarchy

```bash
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar
~/Projects/timur-bar/install.sh
```

Or with Omarchy's plugin manager, which also gives you `omarchy plugin update`:

```bash
omarchy plugin add https://github.com/crsstha/timur-bar.git --enable
~/.config/omarchy/plugins/crsstha.timur/install.sh
```

`install.sh` links the script, starts the refresh timer, adds the plugin to the bar (right side), adds the keybindings, and asks for your session.

### i3

```bash
sudo pacman -S rofi dunst polybar        # or i3blocks instead of polybar
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar
~/Projects/timur-bar/install.sh          # auto-detects i3; or pass --i3
```

Then add the bar module. `install.sh` prints the paths:
- **polybar:** paste `i3/polybar.ini` into your config and add `timur` to `modules-right`.
- **i3blocks:** paste `i3/i3blocks.conf` into `~/.config/i3blocks/config`.

Reload i3 with `$mod+Shift+r`.

## Connect your session

Timur signs in with Google and has no API keys, so `timur-bar` reuses your browser session:

1. Log into the Timur web app → **F12** → **Application** → **Cookies** → `https://timur.dev.togglecorp.com`.
2. Run `timur-bar set-session`, or use **Paste session** in the panel or menu.
3. Paste the **Value** of each cookie:

   | Cookie | |
   |---|---|
   | `__Secure-timur-PROD-sessionid` | your login session |
   | `timur-PROD-csrftoken` | CSRF token |

It's saved to `~/.config/timur-bar/session` (`chmod 600`). Sessions last about a month, and the bar shows `•` three days before expiry.

> ⚠ The session cookie is as good as your password for Timur. Never commit or share it.

## Usage

| | Omarchy | i3 |
|---|---|---|
| Log time | `Super+Alt+T` or left-click | `$mod+Alt+t`, scroll up on the module, or left-click → *Log time* |
| Journal note | `Super+Alt+J` | `$mod+Alt+j` |
| Edit / delete entries | hover an entry in *Logged today* | `$mod+Alt+e` or menu → *Entries* |
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
| i3: no notifications from timers | Make sure the `import-environment` line from `i3/i3.config` is in your i3 config, and that `dunst` is running |

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
