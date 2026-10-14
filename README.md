# timur-bar

Log your time and journal notes to [Timur](https://timur.dev.togglecorp.com/) directly from your desktop bar. You do not need to open the Timur website.

It shows how much time you have logged today in the top bar. Click the time to open a small panel where you can:

* Log time
* Edit or delete today's entries
* Add journal notes

```text
󰔟 5h20      you've logged 5h20 today

󰔟 1h10      after 17:00 and you've logged less than 2h

󰔟 5h20 •    your Timur session expires within 3 days

󰔟 5h20 · 2 todo   i3: two of today's entries are still TODO/DOING

󰔟 5h20  ▶ 0:42    a timer has been running for 42 minutes (⏸ while paused)

󰔟 !         not connected, or your session has expired
```

## Contents

* [Which setup is yours?](#which-setup-is-yours)
* [Before you start](#before-you-start)
* [Install on Omarchy](#install-on-omarchy)
* [Install on i3 (Arch Linux)](#install-on-i3-arch-linux)
* [Install on GNOME (Ubuntu)](#install-on-gnome-ubuntu)
* [Connect your Timur account](#connect-your-timur-account)
* [Everyday use](#everyday-use)
* [Setting it up for someone else / on another computer](#setting-it-up-for-someone-else--on-another-computer)
* [Update](#update) · [Uninstall](#uninstall) · [Troubleshooting](#troubleshooting)
* [How it works](#how-it-works) · [Commands](#commands) · [Notes for maintainers](#notes-for-maintainers)

## Which setup is yours?

| You use…                                | You get                                                                         | Follow                                     |
| --------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------ |
| **Omarchy** (Hyprland)                  | A widget in the Omarchy bar that opens the Timur panel                          | [Install on Omarchy](#install-on-omarchy)  |
| **i3** with **polybar** or **i3blocks** | A bar module that opens the same panel in the top-right corner, plus rofi menus | [Install on i3](#install-on-i3-arch-linux) |
| **GNOME** (Ubuntu's default desktop)    | A GNOME Shell extension in the top bar that opens the i3 panel under it         | [Install on GNOME](#install-on-gnome-ubuntu) |

All versions work in the same way. They use the same script to communicate with Timur.

## Before you start

You need:

* A **Timur account** that you can log into from your browser.
* **Linux with systemd**. A systemd timer refreshes your Timur data every 5 minutes.
* **Python 3**. You do not need to install anything extra for the main script.
* **`~/.local/bin` must be in your `PATH`**. The installer puts the `timur-bar` command there.

Check your `PATH` with:

```bash
echo $PATH
```

If `~/.local/bin` is not there, add this to `~/.profile`, `~/.zshrc`, or `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then open a new terminal.

**About paths in this guide:**

`~` means your home directory.

For example:

```text
/home/yourname
```

The commands in this guide assume that you clone the repository here:

```text
~/Projects/timur-bar
```

If you clone it somewhere else, replace `~/Projects/timur-bar` with your own path.

## Install on Omarchy

### 1. Get the code

Choose one of these options.

#### Option A: Git clone

You can clone the repository anywhere you want:

```bash
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar

cd ~/Projects/timur-bar
```

#### Option B: Omarchy plugin manager

This option lets you update the plugin later using `omarchy plugin update`.

```bash
omarchy plugin add https://github.com/crsstha/timur-bar.git --enable

cd ~/.config/omarchy/plugins/togglecorp.timur
```

### 2. Run the installer

Run this from the `timur-bar` folder:

```bash
./install.sh
```

The installer will:

* Add the `timur-bar` command to `~/.local/bin`.
* Enable the 5-minute refresh timer.
* Add the Timur widget to the right side of the bar.
* Add these shortcuts to `~/.config/hypr/bindings.lua`:

  * `Super+Alt+T`
  * `Super+Alt+J`

### 3. Connect your Timur account

The installer asks you to do this the first time.

See [Connect your Timur account](#connect-your-timur-account).

### 4. Check that it works

* The bar should show `󰔟 0m` or your logged time.
* If it does not appear, run:

```bash
omarchy restart shell
```

* Press `Super+Alt+T` to open the panel.
* Run:

```bash
timur-bar refresh
```

It should print:

```text
{"ok": true}
```

## Install on i3 (Arch Linux)

On i3, clicking the bar module opens **`timur-panel`**.

It is a GTK version of the Omarchy panel and appears in the top-right corner of your screen.

The Omarchy panel (`omarchy/Panel.qml`) only works inside Omarchy, so i3 has its own GTK version.

The older **rofi** menus are also available.

### 1. Install the required packages

Run:

```bash
sudo pacman -S --needed git python python-gobject gtk3 rofi dunst libnotify xdg-utils ttf-nerd-fonts-symbols

sudo pacman -S --needed polybar
```

If you use i3blocks instead of polybar, install:

```bash
sudo pacman -S --needed i3blocks
```

| Package                  | Why you need it                                  |
| ------------------------ | ------------------------------------------------ |
| `python-gobject`, `gtk3` | Used to create the Timur panel                   |
| `rofi`                   | Provides the fallback menus                      |
| `dunst`, `libnotify`     | Shows notifications such as "Logged 1h30 to …"   |
| `xdg-utils`              | Opens Timur in your browser (scroll down)        |
| `ttf-nerd-fonts-symbols` | Provides the `󰔟` icon                           |

If you do not want to use the `󰔟` icon, you can use another icon or text by adding this to `~/.profile`:

```bash
export TIMUR_BAR_ICON="T:"
```

The command:

```bash
timur-bar set-session --window
```

opens a terminal window.

It uses `$TERMINAL` if you have set it.

Otherwise, it looks for one of these terminals:

```text
alacritty
kitty
foot
wezterm
gnome-terminal
xterm
```

### 2. Get the code and run the installer

```bash
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar

cd ~/Projects/timur-bar

./install.sh --i3
```

The installer will:

* Add these commands to `~/.local/bin`:

  * `timur-bar`
  * `timur-panel`
  * `timur-menu`
  * `i3blocks-timur`
* Enable the 5-minute refresh timer.
* Add a Timur configuration block to:

  ```text
  ~/.config/i3/config
  ```

The added block is marked with:

```text
# >>> timur-bar >>>

...

# <<< timur-bar <<<
```

The block:

* Adds these shortcuts:

  * `Super+Alt+t`
  * `Super+Alt+j`
  * `Super+Alt+e`
* Uses `Mod4+Mod1`, so the shortcuts work even if your `$mod` is Super or Alt.
* Makes the Timur panel a floating window without a border.
* Allows the refresh timer to show notifications.

If your i3 config is somewhere else, for example:

```text
~/.i3/config
```

copy the contents of:

```text
~/Projects/timur-bar/i3/i3.config
```

into your i3 config manually.

### 3. Make sure notifications work

If `dunst` does not start automatically, add this to:

```text
~/.config/i3/config
```

```text
exec --no-startup-id dunst
```

### 4. Add Timur to your bar

Choose **one**:

<details open>
<summary><b>polybar</b></summary>

#### 1. Add the Timur module

The usual polybar config file is:

```text
~/.config/polybar/config.ini
```

Run:

```bash
command cat ~/Projects/timur-bar/i3/polybar.ini >> ~/.config/polybar/config.ini
```

**Important:** use `command cat`, not just `cat`.

Your shell may have `cat` aliased to another command such as `bat`. In that case, using plain `cat` can cause problems and may write unwanted text into your config.

#### 2. Add `timur` to `modules-right`

Find the `[bar/...]` section in your polybar config.

Add `timur` to `modules-right`.

Put it last if you want Timur on the top-right:

```ini
modules-right = … date timur
```

#### 3. Make sure the icon font is available

One of your polybar fonts must support the Timur icon.

Any Nerd Font should work.

If you do not have one, add a font such as:

```ini
font-2 = "Symbols Nerd Font:size=11"
```

Use the next available font number.

#### 4. Restart polybar

Run:

```bash
polybar-msg cmd restart
```

Or use your normal polybar launch script.

</details>

<details>
<summary><b>i3blocks</b></summary>

#### 1. Add the Timur block

Create the i3blocks config directory if needed:

```bash
mkdir -p ~/.config/i3blocks
```

Then add the Timur block:

```bash
command cat ~/Projects/timur-bar/i3/i3blocks.conf >> ~/.config/i3blocks/config
```

#### 2. Make sure i3 uses i3blocks

In:

```text
~/.config/i3/config
```

make sure your bar contains:

```text
bar {
    status_command i3blocks
}
```

</details>

### 5. Reload i3

Press:

```text
$mod+Shift+r
```

### 6. Connect your Timur account

The installer asks for your Timur login the first time.

You can also run:

```bash
timur-bar set-session
```

See [Connect your Timur account](#connect-your-timur-account).

### 7. Check that it works

Run:

```bash
timur-bar bar
```

You should see something like:

```text
󰔟 0m
```

The same text should appear in your bar.

You can then:

* Left-click the module, or press `Super+Alt+t`, to open the panel.
* The panel opens in the top-right corner.
* Press `Esc` or click somewhere else to close it.

If the panel covers your bar or leaves a gap, set the bar height.

For example, if your bar is 30 pixels high, add this to `~/.profile`:

```bash
export TIMUR_PANEL_OFFSET=30
```

Change `30` to your actual bar height.

Then log out and log back in.

## Install on GNOME (Ubuntu)

On GNOME, a small GNOME Shell extension shows your logged time on the right of the top bar.

Clicking it opens **`timur-panel`**, the same GTK panel that i3 uses, just under the top bar.

It works on Wayland and X11, and on GNOME Shell 45 to 50 (Ubuntu 24.04 and newer).

### 1. Install the required packages

```bash
sudo apt install git python3 python3-gi gir1.2-gtk-3.0 libnotify-bin xdg-utils
```

`rofi` is optional. Install it if you also want the one-line quick log (`Super+Alt+q`) and the rofi menus.

You do **not** need a Nerd Font on GNOME. The extension uses a normal GNOME icon.

### 2. Get the code and run the installer

```bash
git clone https://github.com/crsstha/timur-bar.git ~/Projects/timur-bar

cd ~/Projects/timur-bar

./install.sh --gnome
```

The installer will:

* Add `timur-bar`, `timur-panel` and `timur-menu` to `~/.local/bin`.
* Enable the 5-minute refresh timer and the end-of-day reminder.
* Link the extension to `~/.local/share/gnome-shell/extensions/timur-bar@crsstha` and enable it.
* Add these shortcuts under **Settings → Keyboard → Custom Shortcuts**:

  * `Super+Alt+t`: log time
  * `Super+Alt+j`: journal note
  * `Super+Alt+q`: quick log (only if `rofi` is installed)

Use `./install.sh --gnome --no-bindings` if you don't want the shortcuts.

### 3. Log out and log back in

On Wayland, GNOME only loads new extensions when you log in.

After logging in again, you should see the clock icon and `0m` (or your logged time) on the right of the top bar.

If it does not appear, run:

```bash
gnome-extensions info timur-bar@crsstha
```

and check that its state is `ENABLED`. You can also turn it on in the **Extensions** app.

### 4. Connect your Timur account

The installer asks for your Timur login the first time.

See [Connect your Timur account](#connect-your-timur-account).

### Using it on GNOME

| Action         | What it does                     |
| -------------- | -------------------------------- |
| Left-click     | Open or close the panel          |
| Right-click    | Open the panel on the Journal tab |
| Middle-click   | Refresh now                      |

Everything inside the panel works as on i3. See [Everyday use](#everyday-use).

## Connect your Timur account

Timur uses Google login and does not provide API keys.

Because of this, `timur-bar` uses your **existing browser login**.

It needs two cookies from your Timur browser session.

### Steps

#### 1. Log into Timur

Open:

https://timur.dev.togglecorp.com/

Log in normally.

#### 2. Open browser developer tools

Press:

```text
F12
```

Then:

* In Chrome: open **Application**
* In Firefox: open **Storage**

Go to:

```text
Cookies
```

Then select:

```text
https://timur.dev.togglecorp.com
```

#### 3. Start the session setup

Run:

```bash
timur-bar set-session
```

Or open the Timur panel and click:

```text
Paste session
```

#### 4. Copy the cookie values

When asked, copy the **Value** column for these two cookies:

| Cookie name                     | What it does                           |
| ------------------------------- | -------------------------------------- |
| `__Secure-timur-PROD-sessionid` | Your Timur login                       |
| `timur-PROD-csrftoken`          | Security token needed when saving data |

The cookies are saved here:

```text
~/.config/timur-bar/session
```

Only your user can read this file.

Your login normally lasts about one month.

The bar shows:

```text
•
```

three days before the session expires.

To log in again, run:

```bash
timur-bar set-session
```

> ⚠ **Important:** These cookies are as sensitive as your Timur password.
>
> Never:
>
> * Commit them to Git.
> * Paste them into chat.
> * Send them to someone else.

## Everyday use

GNOME uses the same panel as i3, so the **i3** column applies to GNOME as well. On GNOME, scrolling on the top-bar item does nothing; use the **Web ↗** button and `timur-menu` instead.

| To…                     | Omarchy                                     | i3                                                                                                        |
| ----------------------- | ------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Open the panel          | `Super+Alt+T` or left-click the widget      | `Super+Alt+t` or left-click the module                                                                    |
| Add a journal note      | `Super+Alt+J`                               | `Super+Alt+j` or right-click the module                                                                   |
| Edit or delete an entry | Hover over the entry under **Logged today** | **Edit** or **Delete** next to the entry under **Logged today**; deleted by mistake? **↶ Undo** (10 s)  |
| Save without clicking   | `Ctrl+Enter`                                | `Ctrl+Enter`                                                                                              |
| Close the panel         | `Esc`                                       | `Esc`, or click somewhere else                                                                            |
| See your week           | Same as i3 →                                | The **WEEK 21h / 40h** strip under the header; click a day to open it                                     |
| Work on another day     | **Yesterday** button                        | **‹** / **›** buttons (`Ctrl+PgUp` / `Ctrl+PgDn`); click the day name (`Ctrl+Home`) to go back to today   |
| Add a TODO              | —                                           | Set status to **TODO** (or DOING) and leave the duration empty                                            |
| Finish a TODO           | —                                           | Click **✓ Done** next to it, enter the duration, **Update**                                               |
| Time a task             | Same as i3 →                                | Pick the task, **▶ Start timer**. The bar shows `▶ 0:42`; **⏸ Pause** / **▶ Resume**; **■ Stop** fills in the duration, then **Save** |
| Refresh now             | Middle-click                                | Middle-click                                                                                              |
| Same work as last time  | —                                           | While today is empty: **⟳ Repeat yesterday** (or Friday, on a Monday) copies its DONE entries to today   |
| End-of-day reminder     | Same as i3 →                                | Weekdays after 17:00 with less than 2h logged: a notification with **Log now** / **In 30 min**            |
| Open Timur in browser   | Right-click                                 | Scroll down on the module, or the **Web ↗** button in the panel                                           |
| Use rofi menus          | —                                           | Scroll up on the module, or run `timur-menu`                                                              |
| Log in one line         | —                                           | `Super+Alt+q`, type `eoc 1.5 fixed login bug` (task words, time, description) or `helix todo write tests` |
| Log your meetings       | Same as i3 →                                | Under **Meetings**, tick the ones that were work and **Log** — see [Google Calendar meetings](#google-calendar-meetings) |

### Logging time

When logging time:

1. Start typing part of the task name.
2. For example:

   ```text
   tc gen
   ```
3. Choose the task using:

   * Arrow keys + `Enter`, or
   * Mouse click.
4. Enter the duration, or click one of **15m 30m 1h 2h 4h**.
   On i3, a **TODO** or **DOING** entry doesn't need a duration — leave it empty and click **Add TODO**.
5. Enter a description.
6. Click **Save**.

Tasks you used during the last 7 days are marked as **recent** and appear first.

The task type is automatically filled using the type you last used for that task.

### Duration format

By default, durations are entered as **hours**.

Add `m` when you want to enter minutes.

| You type         | Saved as                                 |
| ---------------- | ---------------------------------------- |
| `1`              | 1h                                       |
| `1.5`            | 1h30                                     |
| `0.25`           | 15m                                      |
| `1h30` or `1:30` | 1h30                                     |
| `45m`            | 45 minutes                               |
| More than 24h    | Refused because it is probably a mistake |

### Journal

Every journal note is added as a new line:

```text
- HH:MM your text
```

Timur saves the complete journal at once.

Because of this, `timur-bar` reads the latest journal again before saving it.

**Do not edit the same day's journal in the Timur website at the same time.**

### Google Calendar meetings

The panel (Omarchy, i3 and GNOME) can list the meetings from your Google Calendar that you haven't logged yet, so you can log them with a click. It is optional and off until you connect a calendar — from the panel's **⚙** (Omarchy: **⚙ → Link Google Calendar…**; i3 and GNOME: the **Link calendar** button) or with `timur-bar set-calendar`.

**Connect it** (once):

1. In Google Calendar, open **⚙ Settings** → your calendar under **Settings for my calendars** → **Integrate calendar**.
2. Copy **Secret address in iCal format**. If it isn't there, your Google Workspace admin has turned it off.
3. Run:

   ```bash
   timur-bar set-calendar
   ```

   Paste the address and press `Enter` on an empty line. You can paste several (e.g. a team calendar too).

The secret address lets anyone read your calendar, so treat it like a password. It is kept in `~/.config/timur-bar/calendar` (`chmod 600`) and never written to the cache or the log. If you ever share it by mistake, reset it on the same Google Calendar page and run `set-calendar` again.

**Use it:** the **Meetings** section above **Logged today** shows meetings that:

* are on that day, upcoming ones too (one that hasn't ended yet starts unticked),
* have a start and end time (all-day events like holidays are left out),
* you haven't declined,
* and have no entry yet that starts at the same time.

Each meeting is logged as a DONE entry with the meeting title as description, its length as duration (change it if the meeting ran short or long), and its start time. Pick a task and type for a new meeting; the next time the same meeting (or one with the same title) comes up, they are filled in and it is ticked. **⚠** means it overlaps an earlier meeting. **✕** hides a meeting that wasn't work, and every meeting with the same title, on every day, until you restore it from **hidden**.

Google can take a few hours to update the secret address after you change a meeting. Repeating meetings with an unusual rule are left out and named in `~/.cache/timur-bar/log`.

To stop, use **⚙ → Unlink Google Calendar…** in the panel (or `timur-bar clear-calendar`). The tasks it learned and the meetings you hid are kept, in case you link it again.

### Themes

On Omarchy, i3 and GNOME, **⚙ → Appearance…** in the panel opens its settings:

* **Auto / Light / Dark** — Auto follows your desktop's light or dark style, and switches when the desktop does. On Omarchy it goes by how bright the Omarchy theme is.
* **Light theme** and **Dark theme** — the one used in each mode: Desktop (your GTK or Omarchy theme's own colours and accent), Tokyo Night (the original look), Terracotta, Catppuccin, Gruvbox, Monokai or Solarized.

Choices apply at once and are saved in `~/.config/timur-bar/settings`. All three panels read the same file, so a choice made in one shows in the others. Only the panel changes: the bar text keeps following your bar or GNOME's top bar.

## Setting it up for someone else / on another computer

Each person should install `timur-bar` on their own computer and connect their own Timur account.

Nothing is shared between computers or users.

### Setup for another person

1. Install `timur-bar` using the correct instructions:

   * [Omarchy](#install-on-omarchy)
   * [i3](#install-on-i3-arch-linux)

2. The person logs into Timur using **their own browser**.

3. They run:

   ```bash
   timur-bar set-session
   ```

4. They use **their own cookies**.

Never copy:

```text
~/.config/timur-bar/session
```

from one person's computer to another.

Otherwise, time could be logged under the wrong person's account.

### Moving to a new computer

If you are moving to a new computer:

1. Install `timur-bar` again.
2. Run:

   ```bash
   timur-bar set-session
   ```

This is easier and safer than copying the old files.

### Not using Arch?

The main script only needs:

* Python 3
* systemd

For the i3 version, install the equivalent packages for your Linux distribution.

These distributions are not officially tested by the maintainers.

| Distro          | Command                                                                                             |
| --------------- | --------------------------------------------------------------------------------------------------- |
| Debian / Ubuntu | `sudo apt install git python3 python3-gi gir1.2-gtk-3.0 rofi dunst libnotify-bin xdg-utils polybar` |
| Fedora          | `sudo dnf install git python3 python3-gobject gtk3 rofi dunst libnotify xdg-utils polybar`          |

You also need a Nerd Font for the icon.

Or use:

```bash
export TIMUR_BAR_ICON="T:"
```

Then continue from step 2 of [Install on i3](#install-on-i3-arch-linux).

### Not using i3?

You can also use the i3 version on another X11 desktop that supports running a script from its bar, such as polybar.

Point the bar click action to:

```text
~/.local/bin/timur-panel
```

The keybindings and `for_window` rule are specific to i3, so you need to configure those parts yourself for your window manager.

## Update

If you cloned the repository manually:

```bash
cd ~/Projects/timur-bar && git pull
```

If you installed it using the Omarchy plugin manager:

```bash
omarchy plugin update togglecorp.timur
```

Then run:

```bash
./install.sh
```

It is safe to run the installer again. It will use the latest files.

On Omarchy, reload the panel with:

```bash
omarchy restart shell
```

### Updating i3

The installer does **not** automatically replace an existing Timur block in your i3 config.

If you want the latest shortcuts or rules:

1. Open:

   ```text
   ~/.config/i3/config
   ```

2. Delete everything between:

   ```text
   # >>> timur-bar >>>
   ```

   and:

   ```text
   # <<< timur-bar <<<
   ```

   Include both marker lines.

3. Run:

```bash
./install.sh --i3
```

4. Reload i3:

```text
$mod+Shift+r
```

The polybar/i3blocks configuration is also not updated automatically.

If:

```text
i3/polybar.ini
```

has changed, replace the `[module/timur]` section in your polybar config with the new version.

## Uninstall

Run the uninstall command from the folder where you cloned the repository.

### Remove timur-bar but keep your saved login

```bash
~/Projects/timur-bar/uninstall.sh
```

### Remove timur-bar and also delete your saved login and cache

```bash
~/Projects/timur-bar/uninstall.sh --purge
```

The uninstall script:

* Stops the refresh timer.
* Removes the commands from `~/.local/bin`.
* Removes the Timur blocks from:

  * `~/.config/i3/config`
  * `~/.config/hypr/bindings.lua`
* Removes the Omarchy plugin.
* Disables and removes the GNOME extension and its keyboard shortcuts.

It **does not** modify your polybar or i3blocks config.

If you used polybar or i3blocks, remove the `timur` module from those configs yourself.

## Troubleshooting

| What you see                                                            | What to do                                                                                                                                        |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `󰔟 !` or "Not connected"                                               | Your login is missing or expired. Run `timur-bar set-session`                                                                                     |
| "Not logged in" after pasting                                           | You probably copied the wrong cookie. Use the **Value** of `__Secure-timur-PROD-sessionid`                                                        |
| `timur-bar: command not found`                                          | `~/.local/bin` is not in your `PATH`. See [Before you start](#before-you-start)                                                                   |
| "Something unexpected has occurred"                                     | Timur returned a server error. Check `~/.cache/timur-bar/log`                                                                                     |
| "Invalid pk … does not exist"                                           | The task is no longer active. Refresh and choose the task again                                                                                   |
| Omarchy shows old behaviour after an update                             | Run `omarchy restart shell`                                                                                                                       |
| i3 shows `Duplicate keybinding` errors for `timur-menu` / `timur-panel` | Your Timur config is from an older version. Replace the old Timur block as explained in [Update](#update)                                         |
| i3: clicking the module or `Super+Alt+t` does nothing                   | Run `timur-panel` in a terminal to see the error. If you see `Namespace Gtk not available`, install `python-gobject` and `gtk3`                   |
| i3: the panel opens as a normal tiled window                            | The `for_window [class="^Timur-panel$"] ...` rule is missing. Copy it from `i3/i3.config`                                                         |
| i3: the panel is too high/low or covers the bar                         | Set `TIMUR_PANEL_OFFSET` to your bar height                                                                                                       |
| i3: no notifications                                                    | Check that `dunst` is running with `pgrep dunst`. Also check that the `import-environment` line from `i3/i3.config` exists in your i3 config      |
| i3: the module is empty                                                 | Run `timur-bar bar` for polybar or `~/.local/bin/i3blocks-timur` for i3blocks in a terminal and check the error. Also check your bar config paths |
| i3: the icon appears as a box                                           | Install `ttf-nerd-fonts-symbols` and add it as a polybar font, or set `TIMUR_BAR_ICON`                                                            |
| `cat … >> config.ini` freezes                                           | `cat` is probably aliased in your shell. Press `Ctrl+C`, remove any unwanted lines added to the config, and use `command cat`                     |
| Running `cat … >> config.ini` freezes                                   | `cat` is probably aliased in your shell. Press `Ctrl+C`, remove any unwanted lines added to the config, and use `command cat`                     |

## How it works

The basic flow is:

```text
bin/timur-bar
    │
    │ talks to Timur using your saved login
    │
    │ runs every 5 minutes using a systemd user timer
    │
    ▼
~/.cache/timur-bar/state.json
    │
    ├── Omarchy:
    │     omarchy/BarWidget.qml
    │     omarchy/Panel.qml
    │
    ├── i3:
    │     timur-bar bar
    │     i3/timur-panel
    │     i3/timur-menu
    │
    └── GNOME:
          gnome/timur-bar@crsstha/extension.js  (runs timur-bar bar --json)
          i3/timur-panel
```

The important idea is:

* `timur-bar` is the part that communicates with Timur.
* It gets fresh data every 5 minutes.
* The data is saved in `state.json`.
* The bar and panels read that cached data.
* When you want to save something, the UI calls `timur-bar`.
* This means Omarchy, i3 and GNOME use the same backend logic.

### Important files

| File or folder                  | What's inside                                                  |
| ------------------------------- | -------------------------------------------------------------- |
| `~/.config/timur-bar/session`   | Your saved Timur login. Private and protected with `chmod 600` |
| `~/.config/timur-bar/calendar`  | Your Google Calendar secret address(es), `chmod 600` (optional) |
| `~/.config/timur-bar/settings`  | Panel theme: `mode=`, `light=`, `dark=`                        |
| `~/.cache/timur-bar/calendar.json` | Task and type used per meeting, and meetings you hid        |
| `~/.cache/timur-bar/state.json` | Cached tasks, time entries, and journal data                   |
| `~/.cache/timur-bar/log`        | Log of save attempts and their results                         |

## Commands

```bash
timur-bar refresh
# Get fresh data from Timur now

timur-bar set-session [--window]
# Connect or renew your Timur login
# --window opens the session setup in a new terminal

timur-bar clear-session
# Sign out: delete the saved session and the cached timesheet (also ⚙ in the panel)

timur-bar set-calendar [--window]
# Connect Google Calendar (secret iCal address) for the Meetings list

timur-bar clear-calendar
# Unlink Google Calendar (also ⚙ in the panel)

timur-bar bar [--polybar|--i3blocks|--json]
# Print the bar text using cached data
# Does not make a network request

timur-bar add-entry '{"date":"2026-10-08","task":"117","type":"DEVELOPMENT","status":"DONE","duration":90,"description":"…"}'
# Add a time entry

timur-bar update-entry '{"clientId":"01…","description":"…"}'
# Update an existing time entry

timur-bar delete-entry <clientId> [date]
# Delete a time entry

timur-bar add-note <date> "text"
# Add a journal note

timur-bar log-meetings '[{…add-entry fields…,"startTime":"10:00:00","uid":"…","title":"Standup"}]'
# Log meetings and remember their task and type

timur-bar dismiss-meeting <key>
# Stop offering a meeting, and ones with the same title, on every day (no network request)

timur-bar restore-meeting <key>
# Offer a dismissed meeting, and ones with the same title, again on every day (no network request)

timur-panel [journal] [--yesterday]
# i3 and GNOME: open or close the Timur panel

timur-menu [log|note|entries]
# i3: open the rofi menus

tail -n 5 ~/.cache/timur-bar/log | jq .
# Show the last 5 save attempts
```

For commands that use time entries:

* `duration` is in **minutes**.
* `date` must use this format:

  ```text
  YYYY-MM-DD
  ```

### Optional settings

Add these variables to:

```text
~/.profile
```

| Variable             | Default              | What it changes                                                    |
| -------------------- | -------------------- | ------------------------------------------------------------------ |
| `TIMUR_BAR_ICON`     | `󰔟`                 | Icon or text shown before the logged time                          |
| `TIMUR_PANEL_OFFSET` | `30`                 | i3 (not GNOME, where the extension places the panel): distance in pixels between the top of the screen and the panel |
| `TIMUR_WEEK_TARGET`  | `40`                 | i3: weekly hours target shown in the panel's week strip            |
| `TIMUR_REMIND_HOUR`    | `17`               | earliest hour for the reminder (set it in `~/.config/environment.d/timur.conf`, it runs from systemd) |
| `TIMUR_REMIND_MINUTES` | `120`              | no reminder once this many minutes are logged today            |
| `TERMINAL`           | First terminal found | Terminal used by `set-session --window` and `set-calendar --window` |

## Notes for maintainers

* The GraphQL operations used by `timur-bar` are the same operations used by the Timur web app:

  * `Me`
  * `Enums` (`allActiveTasks`)
  * `MyTimeEntries`
  * `Note`
  * `UpdateNote`
  * `CudTimeEntry`

* `CudTimeEntry` uses **`clientId`** to update and delete entries.

* Users can only update or delete their own entries.

* New entries need a **ULID** as the `clientId` because the database column supports a maximum of 26 characters.

* Cookie names come from:

  ```text
  toggle-corp/timur-backend
  main/settings.py
  ```

* Timur's nightly job moves **TODO entries from previous days to today**.

* The Omarchy panel and i3 panel are two versions of the same panel:

  ```text
  omarchy/Panel.qml
  i3/timur-panel
  ```

  If you change one, make the same change in the other.

## License

MIT
