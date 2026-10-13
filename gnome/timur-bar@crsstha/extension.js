// GNOME Shell front end for timur-bar: today's logged time in the top bar.
//
//   left click    open the panel (timur-panel, the same GTK panel as on i3)
//   right click   open the panel on the Journal tab
//   middle click  refresh now
//
// The text comes from `timur-bar bar --json`, which only reads ~/.cache/timur-bar
// (the refresh timer keeps that current), so it is re-read whenever that folder
// changes and every few seconds for the ▶ timer. GTK can't place its own windows
// on Wayland, so this extension moves the panel under the indicator.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const HOME = GLib.get_home_dir();
const BIN = `${HOME}/.local/bin`;
const CACHE = `${HOME}/.cache/timur-bar`;
const TICK_SECONDS = 10;
const PANEL_WM_CLASSES = ['timur-panel', 'Timur-panel', 'com.togglecorp.TimurPanel'];
const PANEL_GAP = 6; // pixels between the panel and the top bar / screen edge

function spawn(argv) {
    try {
        Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
    } catch (e) {
        Main.notifyError('Timur', `Couldn't run ${argv[0]}: ${e.message}. Did you run ./install.sh --gnome?`);
    }
}

const TimurIndicator = GObject.registerClass(
class TimurIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Timur', true);
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        box.add_child(new St.Icon({icon_name: 'preferences-system-time-symbolic', style_class: 'system-status-icon'}));
        this._label = new St.Label({text: '…', y_align: Clutter.ActorAlign.CENTER});
        box.add_child(this._label);
        this.add_child(box);
    }

    setText(text, color) {
        this._label.text = text;
        this._label.style = color ? `color: ${color};` : null;
    }

    vfunc_event(event) {
        const type = event.type();
        if (type === Clutter.EventType.BUTTON_RELEASE) {
            const button = event.get_button();
            if (button === Clutter.BUTTON_PRIMARY)
                spawn([`${BIN}/timur-panel`]);
            else if (button === Clutter.BUTTON_SECONDARY)
                spawn([`${BIN}/timur-panel`, 'journal']);
            else if (button === Clutter.BUTTON_MIDDLE)
                spawn(['systemctl', '--user', '--no-block', 'start', 'timur-bar-refresh.service']);
            return Clutter.EVENT_STOP;
        }
        if (type === Clutter.EventType.TOUCH_END) {
            spawn([`${BIN}/timur-panel`]);
            return Clutter.EVENT_STOP;
        }
        return super.vfunc_event(event);
    }
});

export default class TimurExtension extends Extension {
    enable() {
        this._indicator = new TimurIndicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');
        this._cancellable = new Gio.Cancellable();

        GLib.mkdir_with_parents(CACHE, 0o755);
        this._monitor = Gio.File.new_for_path(CACHE).monitor_directory(Gio.FileMonitorFlags.NONE, null);
        this._monitor.connect('changed', () => this._queueUpdate());
        this._tickId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, TICK_SECONDS, () => {
            this._update();
            return GLib.SOURCE_CONTINUE;
        });
        this._windowCreatedId = global.display.connect('window-created', (_display, win) => this._watchWindow(win));
        this._windows = new Map(); // MetaWindow -> its signal ids
        this._update();
    }

    disable() {
        global.display.disconnect(this._windowCreatedId);
        for (const [win, ids] of this._windows)
            ids.forEach(id => win.disconnect(id));
        this._windows = null;
        GLib.source_remove(this._tickId);
        if (this._debounceId)
            GLib.source_remove(this._debounceId);
        this._debounceId = 0;
        this._monitor.cancel();
        this._monitor = null;
        this._cancellable.cancel();
        this._cancellable = null;
        this._indicator.destroy();
        this._indicator = null;
    }

    _queueUpdate() {
        // state.json is written in a few steps; read it once the writes settle.
        if (this._debounceId)
            GLib.source_remove(this._debounceId);
        this._debounceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
            this._debounceId = 0;
            this._update();
            return GLib.SOURCE_REMOVE;
        });
    }

    _update() {
        let proc;
        try {
            proc = Gio.Subprocess.new([`${BIN}/timur-bar`, 'bar', '--json'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch {
            this._indicator.setText('not installed', '#e06c75');
            return;
        }
        const cancellable = this._cancellable;
        proc.communicate_utf8_async(null, cancellable, (_proc, result) => {
            if (cancellable.is_cancelled())
                return;
            try {
                const [, stdout] = proc.communicate_utf8_finish(result);
                const {text, color} = JSON.parse(stdout);
                this._indicator.setText(text, color);
            } catch {
                this._indicator.setText('!', '#e06c75');
            }
        });
    }

    // ------------------------------------------------------------ panel placement

    _watchWindow(win) {
        const actor = win.get_compositor_private();
        if (!actor)
            return;
        // The wm class (Wayland app id) and size are only reliable once it has drawn.
        const firstFrameId = actor.connect('first-frame', () => {
            actor.disconnect(firstFrameId);
            if (!this._windows || !PANEL_WM_CLASSES.includes(win.get_wm_class()))
                return;
            win.make_above();
            const ids = [
                win.connect('size-changed', () => this._placePanel(win)), // keep its right edge put
                win.connect('unmanaged', () => this._windows?.delete(win)),
            ];
            this._windows.set(win, ids);
            this._placePanel(win);
        });
    }

    _placePanel(win) {
        const monitor = Main.layoutManager.primaryIndex; // where the top bar is
        const area = Main.layoutManager.getWorkAreaForMonitor(monitor);
        const frame = win.get_frame_rect();
        const [indicatorX] = this._indicator.get_transformed_position();
        const right = Math.min(indicatorX + this._indicator.width, area.x + area.width - PANEL_GAP);
        const x = Math.max(area.x + PANEL_GAP, Math.round(right - frame.width));
        const y = area.y + PANEL_GAP;
        if (frame.x !== x || frame.y !== y)
            win.move_frame(true, x, y);
    }
}
