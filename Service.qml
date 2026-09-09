pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/arzdoon"
    readonly property string executable: pluginDir + "/bin/arzdoon"

    property string phase: "loading"
    property string error: ""
    property string providerId: "alanchand"
    property string providerName: "AlanChand"
    property string providerUrl: "https://alanchand.com/"
    property string localUpdatedAt: ""
    property bool stale: false
    property var prices: []
    property var pins: []
    property var providers: []
    property int revision: 0
    property int refreshMinutes: 5
    property string requestedProvider: "alanchand"
    property var pendingActions: []

    function configure(provider: string, minutes: var): void {
        var nextProvider = String(provider || "alanchand");
        var nextMinutes = Math.max(1, parseInt(minutes, 10) || 5);
        refreshMinutes = nextMinutes;
        if (requestedProvider !== nextProvider) {
            requestedProvider = nextProvider;
            refresh();
        }
    }

    function refresh(): void {
        if (fetchProc.running)
            return;
        phase = prices.length ? "refreshing" : "loading";
        error = "";
        fetchProc.command = [executable, "snapshot", "--provider", requestedProvider];
        fetchProc.running = true;
    }

    function queueAction(kind: string, code: string): void {
        var next = pendingActions.slice();
        next.push([kind, String(code), "--provider", providerId]);
        pendingActions = next;
        runNextAction();
    }

    function runNextAction(): void {
        if (actionProc.running || pendingActions.length === 0)
            return;
        var next = pendingActions.slice();
        var args = next.shift();
        pendingActions = next;
        actionProc.command = [executable].concat(args);
        actionProc.running = true;
    }

    function togglePin(code: string): void {
        queueAction("pin", code);
    }

    function applyState(data: var): void {
        pins = data.pins || [];
        revision++;
    }

    function applySnapshot(raw: string): void {
        try {
            var data = JSON.parse(String(raw || ""));
            if (!data.prices || !data.provider)
                throw new Error("invalid provider response");
            prices = data.prices;
            providerId = data.provider.id;
            providerName = data.provider.name;
            providerUrl = data.provider.url;
            localUpdatedAt = data.localUpdatedAt || "";
            stale = data.stale === true;
            providers = data.providers || [];
            applyState(data);
            phase = stale ? "stale" : "ready";
            error = data.error || "";
        } catch (e) {
            phase = prices.length ? "stale" : "error";
            error = String(e);
        }
    }

    property Process fetchProcess: Process {
        id: fetchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applySnapshot(text)
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text || "").trim())
                root.error = String(text).trim()
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0)
                root.phase = root.prices.length ? "stale" : "error";
        }
    }

    property Process actionProcess: Process {
        id: actionProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(String(text || "")));
                } catch (e) {
                    root.error = String(e);
                }
            }
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0)
                root.error = "Could not save selection";
            Qt.callLater(root.runNextAction);
        }
    }

    property Timer refreshTimer: Timer {
        interval: root.refreshMinutes * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
