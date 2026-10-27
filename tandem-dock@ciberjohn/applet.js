'use strict';

// Tandem Dock - a centered dock that mirrors the pinned apps of the main
// panel's grouped window list (GWL) in real time.
//
// The GWL instance stores its pinned apps in
// ~/.config/cinnamon/spices/grouped-window-list@cinnamon.org/<id>.json
// under the "pinned-apps" key. This applet watches that file and rebuilds
// its launchers whenever the pin list changes: pin something on the panel
// and the dock gains it, unpin and the dock loses it.
//
// Features:
// - macOS-style hover zoom with Gaussian falloff to neighbours (same
//   technique as the grouped-window-list hover-zoom patch)
// - hover preview popup listing an app's open windows (title + close),
//   click a row to focus that window
// - click an icon to focus the app's most recent window or launch it,
//   middle-click for a new window

const Applet = imports.ui.applet;
const Cinnamon = imports.gi.Cinnamon;
const Gio = imports.gi.Gio;
const GLib = imports.gi.GLib;
const St = imports.gi.St;
const Main = imports.ui.main;
const Mainloop = imports.mainloop;
const {AppletSettings} = imports.ui.settings;
const {SignalManager} = imports.misc.signalManager;
const Tweener = imports.ui.tweener;

const GWL_DIR = GLib.get_home_dir() + '/.config/cinnamon/spices/grouped-window-list@cinnamon.org';
const ZOOM_SIGMA = 2.0; // falloff: factor = 1 + amp * exp(-d^2 / (2*sigma))

function appWindows(app) {
    if (!app) return [];
    return app.get_windows().filter(w => {
        return w && !w.is_skip_taskbar() && w.get_window_type() === 0; // META_WINDOW_NORMAL
    });
}

class DockIcon {
    constructor(dock, appId, app) {
        this.dock = dock;
        this.appId = appId;
        this.app = app;
        this.finalized = false;

        this.actor = new St.BoxLayout({
            vertical: true,
            style_class: 'tandem-dock-icon-box',
            reactive: true,
            track_hover: true
        });

        this.iconBin = new Cinnamon.Slicer({ style_class: 'tandem-dock-icon' });
        this.iconBin.set_pivot_point(0.5, 0.5);
        this.iconBin.set_child(this.app.create_icon_texture(this.dock.icon_size));
        this.actor.add_child(this.iconBin);

        this.dot = new St.Bin({ style_class: 'tandem-dock-running-dot' });
        this.actor.add_child(this.dot);
        this.dot.hide();

        this._previewTimeout = null;

        this.dock.signals.connect(this.actor, 'enter-event', () => this.onEnter());
        this.dock.signals.connect(this.actor, 'leave-event', () => this.onLeave());
        this.dock.signals.connect(this.actor, 'button-press-event', (a, event) => this.onPress(event));

        this.updateRunningState();
    }

    onEnter() {
        this.dock.updateHoverZoom(this);
        if (this.dock.enable_preview && this._previewTimeout === null) {
            this._previewTimeout = Mainloop.timeout_add(
                this.dock.preview_delay,
                () => {
                    this._previewTimeout = null;
                    this.dock.showPreview(this);
                    return false;
                }
            );
        }
    }

    onLeave() {
        this.dock.updateHoverZoom(null);
        if (this._previewTimeout !== null) {
            Mainloop.source_remove(this._previewTimeout);
            this._previewTimeout = null;
        }
        this.dock.schedulePreviewClose();
    }

    onPress(event) {
        const button = event.get_button();
        if (button === 1) {
            const windows = appWindows(this.app);
            if (windows.length > 0) {
                Main.activateWindow(windows[0], global.get_current_time());
            } else {
                this.app.open_new_window(-1);
            }
        } else if (button === 2) {
            this.app.open_new_window(-1);
        } else if (button === 3) {
            this.dock.showPreview(this);
        }
        return true;
    }

    updateRunningState() {
        if (this.finalized) return;
        const running = appWindows(this.app).length > 0;
        if (this.dock.show_running_dot) {
            running ? this.dot.show() : this.dot.hide();
        } else {
            this.dot.hide();
        }
    }

    refreshIcon() {
        if (this.finalized) return;
        const old = this.iconBin.get_child();
        this.iconBin.set_child(this.app.create_icon_texture(this.dock.icon_size));
        if (old) old.destroy();
    }

    zoomIcon(factor) {
        if (this.finalized) return;
        if (this.iconBin.scale_x === factor) return;
        Tweener.addTween(this.iconBin, {
            scale_x: factor,
            scale_y: factor,
            time: this.dock.zoom_time,
            transition: 'easeOutQuad'
        });
    }

    destroy() {
        if (this.finalized) return;
        this.finalized = true;
        if (this._previewTimeout !== null) {
            Mainloop.source_remove(this._previewTimeout);
            this._previewTimeout = null;
        }
        this.zoomIcon(1.0);
        this.actor.destroy();
    }
}

class PreviewPopup {
    constructor(dock, icon) {
        this.dock = dock;
        this.icon = icon;
        this.finalized = false;

        this.actor = new St.BoxLayout({
            vertical: true,
            style_class: 'tandem-preview-box',
            reactive: true,
            track_hover: true
        });

        const windows = appWindows(icon.app);
        if (windows.length === 0) {
            const label = new St.Label({ text: 'No open windows', style_class: 'tandem-preview-empty' });
            this.actor.add_child(label);
        }

        windows.forEach(w => {
            const row = new St.BoxLayout({ style_class: 'tandem-preview-row', reactive: true, track_hover: true });
            const iconBin = new St.Bin();
            iconBin.set_child(icon.app.create_icon_texture(16));
            row.add_child(iconBin);
            const title = new St.Label({ text: w.get_title() || w.get_wm_class() || 'Window' });
            title.set_style_class_name('tandem-preview-title');
            row.add_child(title);

            const close = new St.Button({ style_class: 'tandem-preview-close', label: 'x' });
            this.dock.signals.connect(close, 'button-press-event', (a, e) => {
                if (e.get_button() === 1) {
                    w.delete(global.get_current_time());
                    this.dock.closePreview();
                }
                return true;
            });
            row.add_child(close);

            this.dock.signals.connect(row, 'button-press-event', (a, e) => {
                if (e.get_button() === 1) {
                    Main.activateWindow(w, global.get_current_time());
                    this.dock.closePreview();
                }
                return true;
            });

            this.actor.add_child(row);
        });

        Main.uiGroup.add_child(this.actor);

        // Position above the icon once we have an allocation.
        const iconActor = icon.actor;
        Mainloop.idle_add(() => {
            if (this.finalized) return false;
            let x, y;
            [x, y] = iconActor.get_transformed_position();
            let w, h;
            w = iconActor.get_transformed_size()[0];
            h = this.actor.get_preferred_size()[3]; // natural height
            x = x + w / 2 - this.actor.get_preferred_size()[2] / 2;
            this.actor.set_position(Math.max(4, Math.round(x)), Math.max(4, Math.round(y - h - 8)));
            this.actor.show();
            this.actor.grab_key_focus();
            return false;
        });

        this.dock.signals.connect(this.actor, 'leave-event', () => this.dock.schedulePreviewClose());
        this.dock.signals.connect(this.actor, 'enter-event', () => this.dock.cancelPreviewClose());
    }

    destroy() {
        if (this.finalized) return;
        this.finalized = true;
        Main.uiGroup.remove_child(this.actor);
        this.actor.destroy();
    }
}

class TandemDock extends Applet.Applet {
    constructor(metadata, orientation, panelHeight, instanceId) {
        super(orientation, panelHeight, instanceId);

        this.metadata = metadata;
        this.instanceId = instanceId;
        this.signals = new SignalManager(null);

        this.settings = new AppletSettings(this, metadata.uuid, instanceId);
        this.settings.bind('icon-size', 'icon_size', () => this.rebuild(true));
        this.settings.bind('show-running-dot', 'show_running_dot', () => this.updateRunningStates());
        this.settings.bind('gwl-settings-file', 'gwl_settings_file', () => this.watchGwlFile());
        this.settings.bind('zoom-factor', 'zoom_factor', () => this.updateHoverZoom(null));
        this.settings.bind('zoom-time', 'zoom_time', null);
        this.settings.bind('enable-preview', 'enable_preview', null);
        this.settings.bind('preview-delay', 'preview_delay', null);

        this.setAllowedLayout(Applet.AllowedLayout.BOTH);

        this.icons = [];
        this.pins = [];
        this.fileMonitor = null;
        this.reloadTimeout = null;
        this.preview = null;
        this.previewCloseTimeout = null;

        this.box = new St.BoxLayout({ style_class: 'tandem-dock-box' });
        this.actor.add_child(this.box);

        // Live window tracking for the running dots. Muffin's MetaDisplay has
        // no window-added/removed signals; hook per-window 'unmanaged' as
        // windows appear instead.
        this._trackedWindows = new Map();
        this.signals.connect(global.display, 'window-created', (display, win) => {
            this._trackWindow(win);
            this.updateRunningStates();
        });
        this.signals.connect(global.display, 'notify::focus-window', () => this.updateRunningStates());
        global.display.list_windows(0).forEach(win => this._trackWindow(win));

        // Reload pins if the app registry changed (newly installed apps).
        this.signals.connect(Cinnamon.AppSystem.get_default(), 'installed-changed', () => this.rebuild(true));

        this.watchGwlFile();
        this.rebuild(true);
    }

    _trackWindow(win) {
        if (!win || this._trackedWindows.has(win)) return;
        this._trackedWindows.set(win, true);
        this.signals.connect(win, 'unmanaged', (w) => {
            this._trackedWindows.delete(w);
            this.updateRunningStates();
        });
    }

    // ---- pin source -------------------------------------------------------

    resolveGwlFile() {
        const preferred = (this.gwl_settings_file || 'auto').trim();
        if (preferred && preferred !== 'auto') {
            return GWL_DIR + '/' + preferred;
        }
        // auto: newest *.json in the GWL config dir
        let best = null;
        let bestMtime = -1;
        try {
            const dir = Gio.file_new_for_path(GWL_DIR);
            const children = dir.enumerate_children(
                Gio.FILE_ATTRIBUTE_STANDARD_NAME + ',' + Gio.FILE_ATTRIBUTE_TIME_MODIFIED,
                Gio.FileQueryInfoFlags.NONE,
                null
            );
            let info;
            while ((info = children.next_file(null)) !== null) {
                const name = info.get_name();
                if (!name.endsWith('.json')) continue;
                const mtime = info.get_attribute_uint64(Gio.FILE_ATTRIBUTE_TIME_MODIFIED);
                if (mtime > bestMtime) {
                    bestMtime = mtime;
                    best = GWL_DIR + '/' + name;
                }
            }
            children.close(null);
        } catch (e) {
            this.logError('Failed to scan GWL config dir: ' + e);
        }
        return best;
    }

    readPins() {
        const path = this.resolveGwlFile();
        if (!path) {
            this.logError('No grouped-window-list settings file found - is the panel applet loaded?');
            return [];
        }
        try {
            const [ok, contents] = Gio.file_new_for_path(path).load_contents(null);
            const data = JSON.parse(imports.byteArray.toString(contents));
            const pins = data['pinned-apps'] && data['pinned-apps'].value;
            return Array.isArray(pins) ? pins : [];
        } catch (e) {
            this.logError('Failed to read pins from ' + path + ': ' + e);
            return [];
        }
    }

    watchGwlFile() {
        if (this.fileMonitor) {
            this.fileMonitor.cancel();
            this.fileMonitor = null;
        }
        const path = this.resolveGwlFile();
        if (!path) return;
        const file = Gio.file_new_for_path(path);
        this.fileMonitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
        this.fileMonitorId = this.signals.connect(this.fileMonitor, 'changed', () => this.scheduleReload());
    }

    scheduleReload() {
        if (this.reloadTimeout !== null) return;
        // GWL rewrites the settings file more than once per pin change;
        // coalesce the monitor events.
        this.reloadTimeout = Mainloop.timeout_add(250, () => {
            this.reloadTimeout = null;
            this.rebuild(true);
            return false;
        });
    }

    // ---- dock rendering ---------------------------------------------------

    rebuild(refreshIcons) {
        const pins = this.readPins();

        // If the GWL settings file was recreated under a different name,
        // re-attach the monitor.
        if (!this.fileMonitor) this.watchGwlFile();

        const same = pins.length === this.pins.length &&
            pins.every((id, i) => id === this.pins[i]);
        if (same && !refreshIcons) return;
        if (same && refreshIcons && this.icons.length === pins.length) return;

        this.closePreview();
        this.pins = pins;

        const appSystem = Cinnamon.AppSystem.get_default();
        this.icons.forEach(icon => icon.destroy());
        this.icons = [];
        this.box.remove_all_children();

        const seen = new Set();
        pins.forEach(id => {
            if (seen.has(id)) return;
            seen.add(id);
            let app = appSystem.lookup_app(id);
            if (!app) app = appSystem.lookup_app(id.replace(/:flatpak$/, ''));
            if (!app) app = appSystem.lookup_desktop_wmclass(id.replace(/:flatpak$/, ''));
            if (!app) {
                this.logError('Cannot resolve pinned app ' + id + ' (not installed?)');
                return;
            }
            const icon = new DockIcon(this, id, app);
            this.icons.push(icon);
            this.box.add_child(icon.actor);
        });
    }

    updateRunningStates() {
        this.icons.forEach(icon => icon.updateRunningState());
        if (this.preview) this.preview.icon.updateRunningState();
    }

    // ---- hover zoom -------------------------------------------------------

    updateHoverZoom(hovered) {
        const hoveredIndex = hovered ? this.icons.indexOf(hovered) : -1;
        this.icons.forEach((icon, i) => {
            const d = hovered ? Math.abs(i - hoveredIndex) : Infinity;
            const amp = Math.max(0, this.zoom_factor - 1);
            icon.zoomIcon(1 + amp * Math.exp(-(d * d) / (2 * ZOOM_SIGMA)));
        });
    }

    // ---- preview popup ----------------------------------------------------

    showPreview(icon) {
        this.cancelPreviewClose();
        this.closePreview();
        this.preview = new PreviewPopup(this, icon);
    }

    schedulePreviewClose() {
        this.cancelPreviewClose();
        this.previewCloseTimeout = Mainloop.timeout_add(250, () => {
            this.previewCloseTimeout = null;
            this.closePreview();
            return false;
        });
    }

    cancelPreviewClose() {
        if (this.previewCloseTimeout !== null) {
            Mainloop.source_remove(this.previewCloseTimeout);
            this.previewCloseTimeout = null;
        }
    }

    closePreview() {
        this.cancelPreviewClose();
        if (this.preview) {
            this.preview.destroy();
            this.preview = null;
        }
    }

    // ---- misc -------------------------------------------------------------

    logError(msg) {
        global.logError('TandemDock: ' + msg);
    }

    on_applet_removed_from_panel() {
        this.closePreview();
        if (this.reloadTimeout !== null) Mainloop.source_remove(this.reloadTimeout);
        if (this.fileMonitor) this.fileMonitor.cancel();
        this.signals.disconnectAll();
        this.icons.forEach(icon => icon.destroy());
        this.icons = [];
    }

    on_applet_reloaded() {
        this.on_applet_removed_from_panel();
    }
}

function main(metadata, orientation, panelHeight, instanceId) {
    return new TandemDock(metadata, orientation, panelHeight, instanceId);
}
