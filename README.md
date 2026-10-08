# timur-bar

Log your time and journal notes to [Timur](https://timur.dev.togglecorp.com/) (Togglecorp's timesheet) straight from your desktop bar, without opening the web app.

It shows how much you've logged today in the top bar. Click it to open a small panel where you can log time, edit or delete today's entries, and add journal notes.

```
 󰔟 5h20      you've logged 5h20 today
 󰔟 1h10      dimmed: it's after 17:00 and you've logged under 2h
 󰔟 5h20 •    your Timur session expires within 3 days
 󰔟 !         not connected, or the session has expired
```

## Contents

- [Which setup is yours?](#which-setup-is-yours)
- [Before you start](#before-you-start)
- [Install on Omarchy](#install-on-omarchy)
- [Install on i3 (Arch Linux)](#install-on-i3-arch-linux)
- [Connect your Timur account](#connect-your-timur-account)
- [Everyday use](#everyday-use)
- [Setting it up for someone else / on another computer](#setting-it-up-for-someone-else--on-another-computer)
- [Update](#update) · [Uninstall](#uninstall) · [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works) · [Commands](#commands) · [Notes for maintainers](#notes-for-maintainers)

## Which setup is yours?

| You use… | You get | Follow |
|---|---|---|
| **Omarchy** (Hyprland) | A widget in Omarchy's bar that opens the Timur panel | [Install on Omarchy](#install-on-omarchy) |
| **i3** with **polybar** or **i3blocks** | A bar module that opens the same panel (GTK popup, top-right corner), plus rofi menus | [Install on i3](#install-on-i3-arch-linux) |

Both versions look and work the same way. They use the same script to talk to Timur.

## Before you start

You need:

- a **Timur account** you can log into in your browser;
- **Linux with systemd**: a timer refreshes your data every 5 minutes;
- **Python 3**: nothing extra to install for the main script;
- **`~/.local/bin` on your `PATH`**: the installer puts the `timur-bar` command there. Check with `echo $PATH`. If it's missing, add `export PATH="$HOME/.local/bin:$PATH"` to `~/.profile` (or `~/.zshrc` / `~/.bashrc`) and open a new terminal.

**About paths in this guide:** `~` means your home folder (for example `/home/yourname`). The commands assume you clone the repo to `~/Projects/timur-bar`. If you clone it somewhere else, use your own path wherever you see `~/Projects/timur-bar`.

## Install on Omarchy

**1. Get the code.** Pick one:

```bash
# Option A: git clone (keep it anywhere you like)
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar
cd ~/Projects/timur-bar
```

```bash
# Option B: Omarchy's plugin manager (lets you update later with `omarchy plugin update`)
omarchy plugin add https://github.com/crsstha/timur-bar.git --enable
cd ~/.config/omarchy/plugins/crsstha.timur
```

**2. Run the installer** from that folder:

```bash
./install.sh
```

It:
- links the `timur-bar` command into `~/.local/bin`;
- turns on the 5-minute refresh timer;
- adds the widget to the right side of the bar;
- adds the shortcuts `Super+Alt+T` and `Super+Alt+J` to `~/.config/hypr/bindings.lua`.

**3. Connect your Timur account.** On the first run the installer asks for this. See [Connect your Timur account](#connect-your-timur-account).

**4. Check it works:**
- The bar shows `󰔟 0m` or your logged time. If it doesn't, run `omarchy restart shell`.
- `Super+Alt+T` opens the panel.
- `timur-bar refresh` prints `{"ok": true}`.

## Install on i3 (Arch Linux)

On i3, clicking the bar module opens **`timur-panel`**, a GTK copy of the Omarchy panel. It appears under your bar in the top-right corner. The Omarchy panel itself (`Panel.qml`) only runs inside Omarchy, which is why i3 has its own copy. The older **rofi** menus are still there too (scroll up on the module).

**1. Install the packages:**

```bash
sudo pacman -S --needed git python python-gobject gtk3 rofi dunst libnotify xdg-utils ttf-nerd-fonts-symbols
sudo pacman -S --needed polybar      # or: sudo pacman -S --needed i3blocks
```

| Package | Why |
|---|---|
| `python-gobject`, `gtk3` | draw the panel |
| `rofi` | the fallback menus |
| `dunst`, `libnotify` | "Logged 1h30 to …" pop-up notifications |
| `xdg-utils` | right-click opens Timur in your browser |
| `ttf-nerd-fonts-symbols` | the `󰔟` icon. Don't want it? Add `export TIMUR_BAR_ICON="T:"` to `~/.profile` |

`timur-bar set-session --window` opens a terminal. It uses `$TERMINAL` if you've set it, otherwise the first of `alacritty`, `kitty`, `foot`, `wezterm`, `gnome-terminal` or `xterm` it finds.

**2. Get the code and run the installer:**

```bash
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar
cd ~/Projects/timur-bar
./install.sh --i3
```

It:
- links `timur-bar`, `timur-panel`, `timur-menu` and `i3blocks-timur` into `~/.local/bin`;
- turns on the 5-minute refresh timer;
- adds a block to the end of **`~/.config/i3/config`**, marked with `# >>> timur-bar >>>` … `# <<< timur-bar <<<`, which:
  - adds the shortcuts **`Super+Alt+t`**, **`Super+Alt+j`** and **`Super+Alt+e`**. They are written as `Mod4+Mod1`, so they work whether your `$mod` is Super or Alt;
  - makes the panel a floating window without a border;
  - lets the refresh timer show notifications.

> If your i3 config is somewhere else (for example `~/.i3/config`), copy the contents of `~/Projects/timur-bar/i3/i3.config` into it yourself.

**3. Make sure notifications show up.** If nothing starts `dunst` yet, add this line to `~/.config/i3/config`:

```
exec --no-startup-id dunst
```

**4. Add the module to your bar.** Choose **one**:

<details open><summary><b>polybar</b></summary>

1. Add the module to the end of your polybar config. The usual file is `~/.config/polybar/config.ini`. Use your own path if your config lives somewhere else.
   ```bash
   command cat ~/Projects/timur-bar/i3/polybar.ini >> ~/.config/polybar/config.ini
   ```
   Use `command cat`, not plain `cat`. If your shell aliases `cat` to something like `bat`, plain `cat` can freeze and write whatever you type next into your config.
2. In your `[bar/…]` section, add `timur` to `modules-right`. Put it **last** to have it in the top-right corner:
   ```ini
   modules-right = … date timur
   ```
3. Make sure one of the bar's fonts has the icon. Any Nerd Font works. If none does, add a font line using the next free number, for example:
   ```ini
   font-2 = "Symbols Nerd Font:size=11"
   ```
4. Restart polybar: `polybar-msg cmd restart`, or your usual launch script.

</details>

<details><summary><b>i3blocks</b></summary>

1. Add the block to your i3blocks config:
   ```bash
   mkdir -p ~/.config/i3blocks
   command cat ~/Projects/timur-bar/i3/i3blocks.conf >> ~/.config/i3blocks/config
   ```
2. Make sure i3's bar uses i3blocks. In `~/.config/i3/config`:
   ```
   bar {
       status_command i3blocks
   }
   ```

</details>

**5. Reload i3:** press `$mod+Shift+r`.

**6. Connect your Timur account.** The installer asks on the first run, or run `timur-bar set-session`. See [Connect your Timur account](#connect-your-timur-account).

**7. Check it works:**
- `timur-bar bar` prints something like `󰔟 0m`.
- The bar shows the same text.
- Left-clicking it, or `Super+Alt+t`, opens the panel in the top-right corner with the cursor in the task search. Click again, press `Esc` or click somewhere else to close it.
- If the panel covers your bar or leaves a gap, set your bar height in pixels: add `export TIMUR_PANEL_OFFSET=30` to `~/.profile`, change `30` to your bar's height, then log out and back in.

## Connect your Timur account

Timur signs in with Google and has no API keys, so timur-bar borrows your **browser login** (two cookies):

1. Log into the [Timur web app](https://timur.dev.togglecorp.com/) in your browser.
2. Press **F12** → **Application** tab (Firefox: **Storage**) → **Cookies** → `https://timur.dev.togglecorp.com`.
3. Run `timur-bar set-session`, or click **Paste session** in the panel.
4. When asked, paste the **Value** column of each cookie:

   | Cookie name | What it is |
   |---|---|
   | `__Secure-timur-PROD-sessionid` | your login |
   | `timur-PROD-csrftoken` | security token Timur needs for saving |

They're saved to `~/.config/timur-bar/session`, which only you can read. A login lasts about a month. The bar shows `•` three days before it runs out. To renew, run `timur-bar set-session` again.

> ⚠ **These cookies are as good as your password for Timur.** Never commit them, paste them in chat, or share them with anyone.

## Everyday use

| To… | Omarchy | i3 |
|---|---|---|
| Open the panel | `Super+Alt+T` or left-click the widget | `Super+Alt+t` or left-click the module |
| Add a journal note | `Super+Alt+J` | `Super+Alt+j` |
| Edit or delete an entry | hover the entry under *Logged today* | *Edit* / *Delete* next to the entry under *Logged today* (`Super+Alt+e` also opens the panel) |
| Save without clicking | `Ctrl+Enter` | `Ctrl+Enter` |
| Close the panel | `Esc` | `Esc`, or click elsewhere |
| Work on yesterday | *Yesterday* button | *Yesterday* button |
| Refresh now | middle-click | middle-click |
| Open Timur in the browser | right-click | right-click |
| rofi menus instead | — | scroll up on the module, or run `timur-menu` |

**Logging time:** type a few letters of the task (for example `tc gen`), pick it with the arrow keys and `Enter` (or a click), then enter the duration and a description, and press **Save**. Tasks you used in the last 7 days are marked *recent* and listed first. The type is filled in with the one you last used for that task.

**Duration is in hours** unless you add `m`:

| You type | Saved as |
|---|---|
| `1` | 1h |
| `1.5` | 1h30 |
| `0.25` | 15m |
| `1h30` or `1:30` | 1h30 |
| `45m` | 45 minutes |
| more than 24h | refused (it's probably a typo) |

**Journal:** each note is added as a new line `- HH:MM your text`. Timur saves the whole journal at once, so timur-bar re-reads it just before saving. Don't edit the same day's journal in the web app at the same moment.

## Setting it up for someone else / on another computer

Each person installs timur-bar on their own computer and connects **their own** Timur account. Nothing is shared between people or computers.

1. Install it with the steps for their setup ([Omarchy](#install-on-omarchy) or [i3](#install-on-i3-arch-linux)).
2. They log into Timur in **their** browser and run `timur-bar set-session` with **their** cookies. Never copy `~/.config/timur-bar/session` from one person to another: it would log time as the wrong person.
3. Moving to a new computer of your own? Install it there and run `timur-bar set-session` again. It's quicker than copying files.

**Not on Arch?** The script itself only needs Python 3 and systemd. For the i3 version, install the same tools with your distro's package names (not tested by the maintainers):

| Distro | Command |
|---|---|
| Debian / Ubuntu | `sudo apt install git python3 python3-gi gir1.2-gtk-3.0 rofi dunst libnotify-bin xdg-utils polybar` |
| Fedora | `sudo dnf install git python3 python3-gobject gtk3 rofi dunst libnotify xdg-utils polybar` |

Then install a Nerd Font for the icon (or set `TIMUR_BAR_ICON="T:"`), and continue from step 2 of [Install on i3](#install-on-i3-arch-linux).

**Not using i3?** On another X11 desktop with a bar that can run a script (such as polybar), the bar module and `timur-panel` should still work. Point the bar's click at `~/.local/bin/timur-panel`. The keybindings and the `for_window` rule are i3-only, so set up the same things in your own window manager.

## Update

```bash
cd ~/Projects/timur-bar && git pull     # Omarchy plugin manager: omarchy plugin update crsstha.timur
./install.sh                            # safe to run again; picks up new files
omarchy restart shell                   # Omarchy only: reloads the panel
```

**i3:** the installer never changes a timur-bar block that's already in your i3 config. To get new shortcuts or rules:

1. Open `~/.config/i3/config` and delete everything from `# >>> timur-bar >>>` to `# <<< timur-bar <<<`, including those two lines.
2. Run `./install.sh --i3` again.
3. Reload i3 (`$mod+Shift+r`).

The polybar / i3blocks module is also never updated for you. If `i3/polybar.ini` changed, replace the `[module/timur]` section in your polybar config with the new one.

## Uninstall

Run it from wherever you cloned the repo:

```bash
~/Projects/timur-bar/uninstall.sh            # keeps your saved login
~/Projects/timur-bar/uninstall.sh --purge    # also deletes your saved login and cached data
```

It stops the timer and removes the links in `~/.local/bin`. It also removes the marked blocks from `~/.config/i3/config` and `~/.config/hypr/bindings.lua`, and the Omarchy plugin. It does **not** touch your polybar or i3blocks config, so remove the `timur` module there yourself.

## Troubleshooting

| What you see | What to do |
|---|---|
| `󰔟 !` or "Not connected" | Your login is missing or expired. Run `timur-bar set-session` |
| "Not logged in" right after pasting | You copied the wrong row. Use the **Value** of `__Secure-timur-PROD-sessionid` |
| `timur-bar: command not found` | `~/.local/bin` isn't on your `PATH` (see [Before you start](#before-you-start)) |
| "Something unexpected has occurred" | Timur had a server error. The request is logged in `~/.cache/timur-bar/log` |
| "Invalid pk … does not exist" | That task is no longer active. Refresh and pick it again |
| Omarchy: panel shows old behaviour after an update | `omarchy restart shell` |
| i3: `Duplicate keybinding` errors for `timur-menu` / `timur-panel` | Your timur-bar block is from an older version (`$mod+Mod1`, which is plain Alt when `$mod` is Alt). Replace it as described in [Update](#update) |
| i3: clicking the module or `Super+Alt+t` does nothing | Run `timur-panel` in a terminal to see the error. `Namespace Gtk not available` means `python-gobject` / `gtk3` are missing |
| i3: the panel opens as a normal tiled window | The `for_window [class="^Timur-panel$"] …` line is missing from your i3 config. Copy it from `i3/i3.config` |
| i3: panel sits on top of the bar or too low | Set `TIMUR_PANEL_OFFSET` to your bar height (see step 7 of the i3 install) |
| i3: no notifications | Make sure `dunst` is running (`pgrep dunst`) and the `import-environment` line from `i3/i3.config` is in your i3 config |
| i3: module is empty | Run `timur-bar bar` (polybar) or `~/.local/bin/i3blocks-timur` (i3blocks) in a terminal to see the error, and check the paths in your bar config |
| i3: the icon is a box | Install `ttf-nerd-fonts-symbols` and add it as a polybar font, or set `TIMUR_BAR_ICON` |
| Running `cat … >> config.ini` freezes | `cat` is aliased in your shell. Press `Ctrl+C`, remove any stray lines it added to the end of the file, and use `command cat` |

## How it works

```
bin/timur-bar ── the only part that talks to Timur (using your saved login)
   │  runs every 5 minutes (systemd user timer) → saves to ~/.cache/timur-bar/state.json
   ▼
Omarchy:  BarWidget.qml (bar) + Panel.qml (panel)
i3:       timur-bar bar (bar text) + i3/timur-panel (GTK panel) + i3/timur-menu (rofi menus)
```

The bar and panels only read `state.json`. To save something they call `timur-bar`, so every front end behaves the same.

| File or folder | What's in it |
|---|---|
| `~/.config/timur-bar/session` | your saved login (private, `chmod 600`) |
| `~/.cache/timur-bar/state.json` | cached tasks, entries and journal |
| `~/.cache/timur-bar/log` | every save attempt and its result |

## Commands

```bash
timur-bar refresh                         # fetch from Timur now
timur-bar set-session [--window]          # connect or renew your login (--window: in a new terminal)
timur-bar bar [--polybar|--i3blocks]      # print the bar text from the cache (no network)
timur-bar add-entry '{"date":"2026-10-08","task":"117","type":"DEVELOPMENT","status":"DONE","duration":90,"description":"…"}'
timur-bar update-entry '{"clientId":"01…","description":"…"}'
timur-bar delete-entry <clientId> [date]
timur-bar add-note <date> "text"
timur-panel [journal] [--yesterday]       # i3: open/close the panel
timur-menu [log|note|entries]             # i3: rofi menus
tail -n 5 ~/.cache/timur-bar/log | jq .   # last 5 save attempts
```

`duration` is in minutes and `date` is `YYYY-MM-DD`.

Optional settings (put them in `~/.profile`):

| Variable | Default | Effect |
|---|---|---|
| `TIMUR_BAR_ICON` | `󰔟` | icon or text shown before the time |
| `TIMUR_PANEL_OFFSET` | `30` | i3: pixels between the top of the screen and the panel |
| `TERMINAL` | first found | terminal used by `set-session --window` |

## Notes for maintainers

- The GraphQL operations are the web app's own: `Me`, `Enums` (`allActiveTasks`), `MyTimeEntries`, `Note`, `UpdateNote` and `CudTimeEntry`.
- `CudTimeEntry` matches **updates and deletes by `clientId`**, limited to your own entries.
- New entries need a **ULID** `clientId`, because the column holds at most 26 characters.
- Cookie names come from `toggle-corp/timur-backend` `main/settings.py`.
- Timur's nightly job **moves TODO entries** from past days to today.
- `Panel.qml` (Omarchy) and `i3/timur-panel` (GTK) are two copies of the same panel. When you change one, change the other to match.

## License

MIT
