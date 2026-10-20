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

    readonly property int maxOutputChars: 2097152
    readonly property int maxRows: 200
    readonly property int maxPins: 32
    readonly property int maxPendingActions: 16
    readonly property int maxErrorChars: 300
    readonly property int fetchDeadlineMs: 30000
    readonly property int actionDeadlineMs: 10000
    readonly property var codePattern: /^[A-Z0-9][A-Z0-9-]{0,11}$/

    function cleanText(value: var, limit: int): string {
        return String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f]+/g, " ").trim().substring(0, limit);
    }

    function safeUrl(value: var): string {
        var text = String(value || "");
        return /^https:\/\/[A-Za-z0-9.-]+(:[0-9]+)?(\/[^\s<>"']*)?$/.test(text) ? text : "";
    }

    function validCode(code: var): bool {
        return codePattern.test(String(code || ""));
    }

    function cleanPrices(rows: var): var {
        var result = [];
        var list = Array.isArray(rows) ? rows : [];
        for (var i = 0; i < list.length && result.length < maxRows; i++) {
            var row = list[i];
            if (!row || typeof row !== "object" || !validCode(row.code))
                continue;
            var buy = Number(row.buy);
            var sell = Number(row.sell);
            result.push({
                code: row.code,
                name: cleanText(row.name, 64),
                buy: row.buy === null || !isFinite(buy) ? null : buy,
                sell: row.sell === null || !isFinite(sell) ? null : sell,
                direction: row.direction === "up" || row.direction === "down" ? row.direction : "flat"
            });
        }
        return result;
    }

    function cleanPins(values: var): var {
        var result = [];
        var list = Array.isArray(values) ? values : [];
        for (var i = 0; i < list.length && result.length < maxPins; i++) {
            if (validCode(list[i]))
                result.push(list[i]);
        }
        return result;
    }

    function cleanProviders(values: var): var {
        var result = [];
        var list = Array.isArray(values) ? values : [];
        for (var i = 0; i < list.length && result.length < 16; i++) {
            var item = list[i];
            if (item && /^[a-z0-9_-]{1,32}$/.test(String(item.id)))
                result.push({
                    id: String(item.id),
                    name: cleanText(item.name, 64),
                    url: safeUrl(item.url)
                });
        }
        return result;
    }

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
        if (!validCode(code) || pendingActions.length >= maxPendingActions)
            return;
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
        pins = cleanPins(data.pins);
        revision++;
    }

    function applySnapshot(raw: string): void {
        try {
            var text = String(raw || "");
            if (text.length > maxOutputChars)
                throw new Error("provider response is too large");
            var data = JSON.parse(text);
            if (!data.prices || !data.provider)
                throw new Error("invalid provider response");
            var cleaned = cleanPrices(data.prices);
            if (!cleaned.length)
                throw new Error("invalid provider response");
            prices = cleaned;
            providerId = cleanText(data.provider.id, 32);
            providerName = cleanText(data.provider.name, 64);
            providerUrl = safeUrl(data.provider.url);
            localUpdatedAt = cleanText(data.localUpdatedAt, 40);
            stale = data.stale === true;
            providers = cleanProviders(data.providers);
            applyState(data);
            phase = stale ? "stale" : "ready";
            error = cleanText(data.error, maxErrorChars);
        } catch (e) {
            phase = prices.length ? "stale" : "error";
            error = cleanText(e, maxErrorChars);
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
                root.error = root.cleanText(text, root.maxErrorChars)
        }
        onRunningChanged: {
            if (running)
                fetchWatchdog.restart();
            else
                fetchWatchdog.stop();
        }
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0)
                root.phase = root.prices.length ? "stale" : "error";
        }
    }

    property Timer fetchWatchdog: Timer {
        interval: root.fetchDeadlineMs
        onTriggered: if (fetchProc.running) {
            fetchProc.running = false;
            root.error = "Price request timed out";
            root.phase = root.prices.length ? "stale" : "error";
        }
    }

    property Timer actionWatchdog: Timer {
        interval: root.actionDeadlineMs
        onTriggered: if (actionProc.running)
            actionProc.running = false
    }

    property Process actionProcess: Process {
        id: actionProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.applyState(JSON.parse(String(text || "")));
                } catch (e) {
                    root.error = root.cleanText(e, root.maxErrorChars);
                }
            }
        }
        onRunningChanged: {
            if (running)
                actionWatchdog.restart();
            else
                actionWatchdog.stop();
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
