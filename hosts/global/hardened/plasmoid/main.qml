// Required so the compact/full representations below, which are Components,
// can bind to `root` from the enclosing scope. Without it Qt resolves those
// lookups dynamically at runtime instead of statically.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    // "full"    - hardened config AND hardened kernel booted
    // "runtime" - hardened config, but still on the normal kernel
    // "home"    - normal config, on a trusted network
    // "off"     - normal config, on an untrusted or unidentified network
    // "unknown" - the helper has not answered yet
    property string mode: "unknown"

    readonly property string modeLabel: {
        switch (mode) {
        case "full":    return "Hardened"
        case "runtime": return "Hardened (runtime only)"
        case "home":    return "Trusted network"
        case "off":     return "Unhardened"
        default:        return "Checking..."
        }
    }

    readonly property string modeDetail: {
        switch (mode) {
        case "full":
            return "Running the hardened configuration on the hardened kernel. "
                 + "USB, DMA and network lockdown are all in effect."
        case "runtime":
            return "Running the hardened configuration, but on the normal kernel. "
                 + "Services are locked down; IOMMU, module blacklists and SMT "
                 + "settings are NOT — reboot into the hardened entry for those."
        case "home":
            return "Connected to a trusted network. Running the normal "
                 + "configuration, which is expected here."
        case "off":
            return "Running the normal configuration on a network that is not "
                 + "in the trusted list. Run 'harden' if you did not mean to be "
                 + "here unprotected."
        default:
            return "Waiting for the state helper."
        }
    }

    readonly property string modeIcon: {
        switch (mode) {
        case "full":    return "security-high"
        case "runtime": return "security-medium"
        case "home":    return "go-home"
        case "off":     return "security-low"
        default:        return "system-help"
        }
    }

    // Only "at home, unhardened" is genuinely uninteresting, so that is the one
    // state that hides in the tray popup. Being hardened is worth seeing, and
    // being unhardened on an untrusted network is worth seeing *more* -- that
    // is the case auto-arming exists to catch, so a visible icon is the tell
    // that it did not fire.
    Plasmoid.status: mode === "home" || mode === "unknown"
        ? PlasmaCore.Types.PassiveStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: modeLabel
    toolTipSubText: modeDetail

    preferredRepresentation: compactRepresentation

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            var out = (data["stdout"] || "").trim()
            if (out.length > 0) {
                root.mode = out
            }
            disconnectSource(source)
        }
    }

    function refresh() {
        // Reconnecting an already-connected source is a no-op, so drop it first
        // to guarantee the command actually re-runs on every tick.
        executable.disconnectSource("@stateCommand@")
        executable.connectSource("@stateCommand@")
    }

    Timer {
        interval: 5000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    compactRepresentation: Kirigami.Icon {
        source: root.modeIcon
        active: compactMouse.containsMouse

        MouseArea {
            id: compactMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: root.modeIcon
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                }

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: root.modeLabel
                    wrapMode: Text.WordWrap
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.modeDetail
                wrapMode: Text.WordWrap
                opacity: 0.8
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
