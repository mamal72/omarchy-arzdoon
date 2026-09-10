pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "arzdoon"
    ipcTarget: "arzdoon"
    manageIpc: false

    readonly property var service: bar && bar.shell ? bar.shell.serviceFor("arzdoon") : null
    readonly property color fg: bar ? bar.barForeground : Color.foreground
    readonly property color dim: Qt.darker(fg, 1.45)
    readonly property string family: bar ? bar.fontFamily : Style.font.family
    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int maxPinned: Math.max(1, parseInt(setting("maxPinned", 3), 10) || 3)
    readonly property real tablePadding: Style.spacing.rowPaddingX
    readonly property real tableColumnGap: Style.space(8)
    readonly property real barColumnWidth: Style.space(96)
    readonly property real tableInnerWidth: Math.max(0, panelScroll.availableWidth - tablePadding * 2 - barColumnWidth - tableColumnGap * 3)
    readonly property real currencyColumnWidth: Style.space(56)
    readonly property real buyColumnWidth: (tableInnerWidth - currencyColumnWidth) * 0.48
    readonly property real sellColumnWidth: tableInnerWidth - currencyColumnWidth - buyColumnWidth
    readonly property var rows: {
        if (!service)
            return [];
        service.revision;
        return Model.sortedRows(service.prices, service.pins);
    }
    readonly property string barLabel: service ? Model.barLabel(service.prices, service.pins, maxPinned, vertical) : "$"
    readonly property real openPanelIndicatorWidth: button.labelWidth
    readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
    property string activeSection: "rates"

    function configureService(): void {
        if (service)
            service.configure(setting("provider", "alanchand"), setting("refreshMinutes", 5));
    }

    function toggleBarCurrency(code: string, pinned: bool): void {
        if (!service)
            return;
        if (pinned || service.pins.length < maxPinned)
            service.togglePin(code);
    }

    function persistSettings(values: var): void {
        var entry = {
            id: root.moduleName
        };
        for (var existing in root.settings) {
            if (existing !== "id")
                entry[existing] = root.settings[existing];
        }
        for (var key in values)
            entry[key] = values[key];
        root.settings = entry;
        if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);
    }

    function setRefreshMinutes(value: var): void {
        var minutes = Math.max(1, Math.min(60, parseInt(value, 10) || 5));
        persistSettings({
            refreshMinutes: minutes
        });
    }

    function providerOptions(): var {
        if (!service || !service.providers || service.providers.length === 0)
            return [
                {
                    value: "alanchand",
                    label: "AlanChand"
                }
            ];
        return service.providers.map(function (provider) {
            return {
                value: String(provider.id),
                label: String(provider.name)
            };
        });
    }

    function setProvider(value: string): void {
        persistSettings({
            provider: String(value || "alanchand")
        });
    }

    Component.onCompleted: configureService()
    onSettingsChanged: configureService()
    onServiceChanged: configureService()

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    IpcHandler {
        target: "arzdoon"
        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function show(): void {
            root.open();
        }
        function hide(): void {
            root.close();
        }
        function toggle(): void {
            root.toggle();
        }
        function refresh(): void {
            if (root.service)
                root.service.refresh();
        }
        function pin(code: string): void {
            if (root.service)
                root.service.togglePin(code);
        }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.barLabel
        fontSize: vertical ? Style.font.icon : Style.font.bodySmall
        tooltipText: service && service.prices.length ? "Arzdoon · " + service.prices.length + " currencies" : "Arzdoon · currency prices"
        active: service && service.phase === "error"
        onPressed: function (mouseButton) {
            if (!root.service)
                return;
            if (mouseButton === Qt.MiddleButton)
                root.service.refresh();
            else
                root.toggle();
        }
    }

    KeyboardPanel {
        id: popup
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: popup.fittedContentWidth(Style.space(540))
        contentHeight: root.activeSection === "rates" ? popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(460)) : popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(650))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onTextKey: function (key) {
                var lower = String(key).toLowerCase();
                if (lower === "r" && root.service)
                    root.service.refresh();
            }

            ScrollView {
                id: panelScroll
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                Column {
                    id: contentColumn
                    width: panelScroll.availableWidth
                    spacing: Style.spacing.panelGap

                    PanelHero {
                        width: parent.width
                        title: "Arzdoon"
                        meta: service ? Model.freshness(service.stale) : "Starting price service…"
                        detail: ""
                        foreground: root.fg
                        fontFamily: root.family
                        iconComponent: Rectangle {
                            width: Style.space(44)
                            height: width
                            radius: Style.cornerRadius
                            color: Style.selectedFillFor(root.fg, Color.accent)
                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: root.fg
                                font.family: root.family
                                font.pixelSize: Style.font.display
                                font.bold: true
                            }
                        }
                    }

                    Text {
                        visible: service && service.localUpdatedAt !== ""
                        width: parent.width
                        textFormat: Text.PlainText
                        text: service ? Model.localUpdateTime(service.localUpdatedAt) : ""
                        color: root.dim
                        font.family: root.family
                        font.pixelSize: Style.font.bodySmall
                        horizontalAlignment: Text.AlignLeft
                    }

                    ButtonGroup {
                        id: sectionTabs
                        options: [
                            {
                                value: "rates",
                                label: "Rates"
                            },
                            {
                                value: "settings",
                                label: "Settings"
                            },
                            {
                                value: "about",
                                label: "About"
                            }
                        ]
                        value: root.activeSection
                        foreground: root.fg
                        fontFamily: root.family
                        focusable: false
                        onChanged: function (value) {
                            root.activeSection = value;
                        }
                    }

                    Column {
                        id: ratesSection
                        visible: root.activeSection === "rates"
                        width: parent.width
                        spacing: Style.spacing.panelGap

                        Item {
                            width: parent.width
                            height: Math.max(ratesTitle.implicitHeight, tableRefresh.implicitHeight)

                            PanelSectionHeader {
                                id: ratesTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: service ? service.prices.length + " Currencies" : "Currency Rates"
                                foreground: root.fg
                                fontFamily: root.family
                            }
                            PanelActionButton {
                                id: tableRefresh
                                anchors.left: ratesTitle.right
                                anchors.leftMargin: Style.spacing.sm
                                anchors.verticalCenter: parent.verticalCenter
                                iconText: service && service.phase === "refreshing" ? "󰦖" : "󰑐"
                                tooltipText: "Refresh Prices (R)"
                                foreground: root.dim
                                fontFamily: root.family
                                onClicked: if (root.service)
                                    root.service.refresh()
                            }
                        }

                        PanelSeparator {
                            width: parent.width
                            foreground: root.fg
                        }

                        Rectangle {
                            width: parent.width
                            height: Style.space(30)
                            radius: Style.cornerRadius
                            color: Style.normalFillFor(root.fg, Color.accent)
                            Row {
                                x: root.tablePadding
                                width: Math.max(0, panelScroll.availableWidth - root.tablePadding * 2)
                                height: parent.height
                                spacing: root.tableColumnGap
                                Text {
                                    width: root.currencyColumnWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Code"
                                    color: root.dim
                                    font.family: root.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    width: root.buyColumnWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Buy"
                                    color: root.dim
                                    font.family: root.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    width: root.sellColumnWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Sell"
                                    color: root.dim
                                    font.family: root.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    width: root.barColumnWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Show in Bar"
                                    color: root.dim
                                    font.family: root.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }

                        Text {
                            visible: !service || service.phase === "loading"
                            width: parent.width
                            text: "Fetching Iranian currency prices…"
                            color: root.dim
                            font.family: root.family
                            font.pixelSize: Style.font.body
                            horizontalAlignment: Text.AlignHCenter
                            topPadding: Style.spacing.xxl
                            bottomPadding: Style.spacing.xxl
                        }

                        Column {
                            visible: service && service.phase === "error" && service.prices.length === 0
                            width: parent.width
                            spacing: Style.spacing.lg
                            Text {
                                width: parent.width
                                text: "Could not load prices. Check the connection and refresh."
                                color: Color.urgent
                                font.family: root.family
                                font.pixelSize: Style.font.body
                                wrapMode: Text.WordWrap
                            }
                            Button {
                                bordered: true
                                text: "Try Again"
                                foreground: root.fg
                                fontFamily: root.family
                                onClicked: root.service.refresh()
                            }
                        }

                        Column {
                            id: rowsColumn
                            visible: root.rows.length > 0
                            width: parent.width
                            spacing: Style.spacing.xs

                            Repeater {
                                model: root.rows
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: rowsColumn.width
                                    height: Style.space(48)
                                    radius: Style.cornerRadius
                                    color: rowHover.hovered ? Style.hoverFillFor(root.fg, Color.accent) : (modelData.pinned ? Style.selectedFillFor(root.fg, Color.accent) : "transparent")

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.tablePadding
                                        anchors.rightMargin: root.tablePadding
                                        spacing: root.tableColumnGap

                                        Item {
                                            width: root.currencyColumnWidth
                                            height: parent.height
                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Style.space(30)
                                                height: width
                                                radius: Math.min(8, Style.cornerRadius)
                                                color: Style.normalFillFor(root.fg, Color.accent)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.code.substring(0, 3)
                                                    color: root.fg
                                                    font.family: root.family
                                                    font.pixelSize: Style.font.caption
                                                    font.bold: true
                                                }
                                            }
                                        }
                                        Text {
                                            width: root.buyColumnWidth
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Model.formatPrice(modelData.buy)
                                            color: root.fg
                                            font.family: root.family
                                            font.pixelSize: Style.font.body
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Text {
                                            width: root.sellColumnWidth
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Model.formatPrice(modelData.sell) + "  " + Model.directionGlyph(modelData.direction)
                                            color: modelData.direction === "down" ? Color.urgent : root.fg
                                            font.family: root.family
                                            font.pixelSize: Style.font.body
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Item {
                                            width: root.barColumnWidth
                                            height: parent.height
                                            ToggleSwitch {
                                                anchors.centerIn: parent
                                                checked: modelData.pinned
                                                interactive: modelData.pinned || root.service.pins.length < root.maxPinned
                                                opacity: interactive ? 1 : 0.45
                                                foreground: root.fg
                                                onToggled: root.toggleBarCurrency(modelData.code, modelData.pinned)
                                            }
                                        }
                                    }

                                    HoverHandler {
                                        id: rowHover
                                    }
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: Math.max(unitLabel.implicitHeight, sourceLink.implicitHeight)
                            Text {
                                id: unitLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Prices in Toman"
                                color: root.dim
                                font.family: root.family
                                font.pixelSize: Style.font.caption
                            }
                            Text {
                                id: sourceLink
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, Math.max(0, parent.width - unitLabel.width - Style.spacing.lg))
                                text: service ? "Source: " + service.providerName + "  ↗" : ""
                                color: root.fg
                                font.family: root.family
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
                                font.underline: sourceMouse.containsMouse
                                MouseArea {
                                    id: sourceMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (service && service.providerUrl)
                                        Quickshell.execDetached(["xdg-open", service.providerUrl])
                                }
                            }
                        }
                    }

                    Column {
                        id: settingsSection
                        visible: root.activeSection === "settings"
                        width: parent.width
                        spacing: Style.spacing.panelGap

                        PanelSeparator {
                            width: parent.width
                            foreground: root.fg
                        }
                        PanelSectionHeader {
                            text: "Update Rate"
                            foreground: root.fg
                            fontFamily: root.family
                        }
                        Text {
                            width: parent.width
                            text: "Choose how often Arzdoon fetches fresh market prices."
                            color: root.dim
                            font.family: root.family
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                        }
                        Rectangle {
                            width: parent.width
                            implicitHeight: refreshSettingsContent.implicitHeight + Style.spacing.rowPaddingX * 2
                            radius: Style.cornerRadius
                            color: Style.normalFillFor(root.fg, Color.accent)

                            Column {
                                id: refreshSettingsContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Style.spacing.rowPaddingX
                                anchors.rightMargin: Style.spacing.rowPaddingX
                                spacing: Style.spacing.lg

                                ButtonGroup {
                                    options: [
                                        {
                                            value: "1",
                                            label: "1 min"
                                        },
                                        {
                                            value: "5",
                                            label: "5 min"
                                        },
                                        {
                                            value: "10",
                                            label: "10 min"
                                        },
                                        {
                                            value: "15",
                                            label: "15 min"
                                        },
                                        {
                                            value: "30",
                                            label: "30 min"
                                        },
                                        {
                                            value: "60",
                                            label: "60 min"
                                        }
                                    ]
                                    value: String(service ? service.refreshMinutes : root.setting("refreshMinutes", 5))
                                    foreground: root.fg
                                    fontFamily: root.family
                                    fontSize: Style.font.bodySmall
                                    focusable: false
                                    onChanged: function (value) {
                                        root.setRefreshMinutes(value);
                                    }
                                }
                                Text {
                                    text: "Saved automatically · next refresh uses the new interval"
                                    color: root.dim
                                    font.family: root.family
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }

                        PanelSeparator {
                            width: parent.width
                            foreground: root.fg
                        }
                        PanelSectionHeader {
                            text: "Price Provider"
                            foreground: root.fg
                            fontFamily: root.family
                        }
                        Text {
                            width: parent.width
                            text: "Select the source used for currency prices."
                            color: root.dim
                            font.family: root.family
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                        }
                        ButtonGroup {
                            options: root.providerOptions()
                            value: String(service ? service.providerId : root.setting("provider", "alanchand"))
                            foreground: root.fg
                            fontFamily: root.family
                            focusable: false
                            onChanged: function (value) {
                                root.setProvider(value);
                            }
                        }
                    }

                    Column {
                        id: aboutSection
                        visible: root.activeSection === "about"
                        width: parent.width
                        spacing: Style.spacing.panelGap

                        PanelSeparator {
                            width: parent.width
                            foreground: root.fg
                        }
                        PanelSectionHeader {
                            text: "About Arzdoon"
                            foreground: root.fg
                            fontFamily: root.family
                        }
                        Text {
                            width: parent.width
                            text: "A native Omarchy bar plugin for live Iranian currency prices."
                            color: root.fg
                            font.family: root.family
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: "Created and maintained by Mohamad Jahani."
                            color: root.dim
                            font.family: root.family
                            font.pixelSize: Style.font.bodySmall
                        }
                        Button {
                            bordered: true
                            text: "GitHub Repository  ↗"
                            tooltipText: "https://github.com/mamal72/omarchy-arzdoon"
                            foreground: root.fg
                            fontFamily: root.family
                            onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/mamal72/omarchy-arzdoon"])
                        }
                        PanelSeparator {
                            width: parent.width
                            foreground: root.fg
                        }
                        PanelSectionHeader {
                            text: "Support My Work"
                            foreground: root.fg
                            fontFamily: root.family
                        }
                        Button {
                            bordered: true
                            text: "Buy Me a Coffee  ↗"
                            tooltipText: "https://buymeacoffee.com/mamal72"
                            foreground: root.fg
                            fontFamily: root.family
                            onClicked: Quickshell.execDetached(["xdg-open", "https://buymeacoffee.com/mamal72"])
                        }
                        PanelSeparator {
                            width: parent.width
                            foreground: root.fg
                        }
                        PanelSectionHeader {
                            text: "Find Me Online"
                            foreground: root.fg
                            fontFamily: root.family
                        }
                        Row {
                            spacing: Style.spacing.lg
                            Button {
                                bordered: true
                                text: "  X · @mamal72"
                                tooltipText: "https://x.com/mamal72"
                                foreground: root.fg
                                fontFamily: root.family
                                onClicked: Quickshell.execDetached(["xdg-open", "https://x.com/mamal72"])
                            }
                            Button {
                                bordered: true
                                text: "  GitHub · @mamal72"
                                tooltipText: "https://github.com/mamal72"
                                foreground: root.fg
                                fontFamily: root.family
                                onClicked: Quickshell.execDetached(["xdg-open", "https://github.com/mamal72"])
                            }
                        }
                        Text {
                            width: parent.width
                            text: "Version 1.0.2 · MIT License"
                            color: root.dim
                            font.family: root.family
                            font.pixelSize: Style.font.caption
                        }
                    }
                }
            }
        }
    }
}
