/*
 * Tandem Dock for Plasma - P1 (pin mirroring)
 *
 * Mirrors the launchers of the Plasma task manager exactly the way the
 * Cinnamon reference implementation mirrors the grouped window list
 * (see ../SPEC.md). This is the P1 draft: not yet verified on a live
 * Plasma 6 session (verification checklist: docs/plasma-port.md).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15

import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.taskmanager 0.1 as TaskManager

PlasmoidItem {
    id: root

    // Floating look: no default panel-applet background; the glass tray
    // behind the icons arrives in P3.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // The mirrored launcher list, parsed out of the task manager applet's
    // config in plasma-org.kde.plasma.desktop-appletsrc.
    property var mirroredLaunchers: []

    // Soft placeholder scale for future phases (magnification is P2).
    readonly property int restSize: Math.floor(height * 0.75)

    TaskManager.TasksModel {
        id: tasksModel
        // One entry per app: pinned launchers merge with their windows,
        // so a running pinned app stays a single icon (group parent).
        groupMode: TaskManager.TasksModel.GroupApplication
        launcherList: root.mirroredLaunchers
    }

    // Pin mirroring source. Plasma rewrites appletsrc on every pin change
    // but offers no QML-visible file watcher, so the file is polled.
    // P1 verify-on-device: the executable engine's command quoting
    // (sh -c '...') must resolve to a live grep on the target machine.
    P5Support.DataSource {
        id: pinSource
        engine: "executable"
        interval: 5000
        property string command:
            "sh -c 'grep -h ^launchers= $HOME/.config/plasma-org.kde.plasma.desktop-appletsrc'"
        connectedSources: [command]
        onNewData: function(source, data) {
            const out = (data["stdout"] || "").trim();
            let best = "";
            if (out) {
                // Several task managers may exist (extra panels). Mirror
                // the one with the largest pin list, the way the Cinnamon
                // reference picks the most-recently-changed GWL instance.
                for (const line of out.split("\n")) {
                    const list = line.slice("launchers=".length).trim();
                    if (list.length > best.length) {
                        best = list;
                    }
                }
            }
            root.mirroredLaunchers = best
                ? best.split(",").map(s => s.trim()).filter(s => s.length > 0)
                : [];
        }
    }

    contentItem: Item {
        id: dockItem
        anchors.fill: parent

        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: PlasmaCore.Units.smallSpacing * 2

            Repeater {
                model: tasksModel
                DockIcon {}
            }
        }

        // Placeholder while there is nothing to mirror (mirrors the
        // Cinnamon behaviour of an empty dock when the task manager
        // instance is gone).
        Text {
            anchors.centerIn: parent
            visible: tasksModel.launcherCount === 0
            text: i18n("Tandem: no task manager pins found")
            color: Kirigami.Theme.disabledTextColor
            font: Kirigami.Theme.smallFont
        }
    }

    Layout.minimumWidth: Math.max(dockRow.implicitWidth, PlasmaCore.Units.gridUnit)
    Layout.minimumHeight: PlasmaCore.Units.gridUnit
    Layout.preferredWidth: dockRow.implicitWidth

    component DockIcon: Item {
        id: iconCell

        property int cellSize: Math.min(Math.floor(dockItem.height * 0.85), 40)
        width: cellSize
        height: cellSize

        // Top-level model index for this row (group children use the
        // two-argument form, not needed at P1).
        function modelIndex() {
            return tasksModel.makeModelIndex(index);
        }

        Kirigami.Icon {
            anchors.fill: parent
            source: model.decoration
            isMask: false
            // Simple hover grow as a P2 placeholder; the Gaussian
            // magnification with neighbour falloff replaces this in P2.
            scale: mouseArea.containsMouse ? 1.15 : 1.0
            Behavior on scale {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }
        }

        // Running indicator: an item that is not a pure launcher has at
        // least one open window (with GroupApplication the running group
        // parent is exactly the merged launcher).
        Rectangle {
            visible: !model.IsLauncher
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: visible ? Math.max(3, Math.round(cellSize / 12)) : 0
            height: width
            radius: width / 2
            color: Kirigami.Theme.highlightColor
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.MiddleButton) {
                    // New window, mirroring the Cinnamon middle-click.
                    tasksModel.requestNewInstance(iconCell.modelIndex());
                    return;
                }
                // Left click: focus the most recent window, or launch
                // (requestActivate on a pure launcher starts the app).
                if (model.IsMinimized === true) {
                    tasksModel.requestToggleMinimized(iconCell.modelIndex());
                }
                tasksModel.requestActivate(iconCell.modelIndex());
            }
        }

        // Group cycling and the window-list preview popup (right click /
        // hover, 350 ms) arrive in P4.
    }
}
