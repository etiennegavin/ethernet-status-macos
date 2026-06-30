import AppKit

enum SpeedState { case idle, running, done(String) }

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let monitor = NetworkMonitor()
    private var interfaces: [NetworkInterface] = []
    private var speedStates: [String: SpeedState] = [:]
    private var collapsedInterfaces: Set<String> = []
    private var prevBytes: [String: (rx: UInt64, tx: UInt64, time: Date)] = [:]
    private var liveSpeed: [String: (down: Double, up: Double)] = [:]
    private var timer: Timer?
    private var lastIconSymbol = ""
    private var lastIconTinted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setButtonImage("cable.connector", tint: nil)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Data

    private func refresh() {
        let prevSnapshot = prevBytes
        let now = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ifaces = self.monitor.fetchInterfaces()

            var netstatData: [String: (rx: UInt64, tx: UInt64)] = [:]
            for iface in ifaces where iface.isConnected {
                if let bytes = self.monitor.netstatBytes(for: iface.deviceName) {
                    netstatData[iface.deviceName] = bytes
                }
            }

            DispatchQueue.main.async {
                var newSpeed: [String: (down: Double, up: Double)] = [:]
                for (dev, bytes) in netstatData {
                    if let prev = prevSnapshot[dev] {
                        let dt = now.timeIntervalSince(prev.time)
                        if dt > 0.5 {
                            let rxDiff = bytes.rx >= prev.rx ? bytes.rx - prev.rx : 0
                            let txDiff = bytes.tx >= prev.tx ? bytes.tx - prev.tx : 0
                            newSpeed[dev] = (Double(rxDiff) / dt / 125_000,
                                            Double(txDiff) / dt / 125_000)
                        }
                    }
                    self.prevBytes[dev] = (bytes.rx, bytes.tx, now)
                }
                self.interfaces = ifaces
                self.liveSpeed  = newSpeed
                self.updateIcon()
                self.buildMenu()
            }
        }
    }

    // MARK: - Icon

    private func updateIcon() {
        let ethConnected  = interfaces.contains(where: { $0.type == .ethernet && $0.isConnected })
        let wifiConnected = interfaces.contains(where: { $0.type == .wifi    && $0.isConnected })
        let anyConnected  = ethConnected || wifiConnected

        let symbol: String
        if ethConnected       { symbol = "cable.connector" }
        else if wifiConnected { symbol = "wifi" }
        else                  { symbol = "cable.connector.slash" }

        setButtonImage(symbol, tint: anyConnected ? nil : .systemRed)
    }

    private func setButtonImage(_ symbol: String, tint: NSColor?) {
        guard let button = statusItem.button else { return }
        let tinted = (tint != nil)
        if symbol != lastIconSymbol || tinted != lastIconTinted {
            lastIconSymbol = symbol
            lastIconTinted = tinted
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                   ?? NSImage(systemSymbolName: "cable.connector", accessibilityDescription: nil)
            img?.isTemplate = !tinted
            button.image = img
        }
        button.contentTintColor = tint
        button.title = ""
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        let order = monitor.serviceOrder()

        let sorted = interfaces.sorted {
            (order.firstIndex(of: $0.serviceName) ?? 999) <
            (order.firstIndex(of: $1.serviceName) ?? 999)
        }

        if sorted.isEmpty {
            menu.addItem(info(Strings.noAdapters))
        } else {
            for (i, iface) in sorted.enumerated() {
                if i > 0 { menu.addItem(.separator()) }
                addSection(iface, to: menu)
            }
        }

        // ── Netzwerk-Reihenfolge ──
        if sorted.count > 1 {
            menu.addItem(.separator())
            menu.addItem(sectionHeader(Strings.networkOrder))

            for (idx, iface) in sorted.enumerated() {
                let badge = iface.isConnected ? " ●" : ""
                menu.addItem(info("  \(idx + 1). \(iface.serviceName)\(badge)"))

                if idx > 0 {
                    let up = NSMenuItem(title: Strings.moveUp, action: #selector(doMoveUp(_:)), keyEquivalent: "")
                    up.target = self; up.representedObject = iface.serviceName; menu.addItem(up)
                }
                if idx < sorted.count - 1 {
                    let dn = NSMenuItem(title: Strings.moveDown, action: #selector(doMoveDown(_:)), keyEquivalent: "")
                    dn.target = self; dn.representedObject = iface.serviceName; menu.addItem(dn)
                }
            }
        }

        // ── Footer ──
        menu.addItem(.separator())
        let r = NSMenuItem(title: Strings.refresh, action: #selector(doRefresh), keyEquivalent: "r")
        r.target = self; menu.addItem(r)
        let s = NSMenuItem(title: Strings.netSettings, action: #selector(doSettings), keyEquivalent: ",")
        s.target = self; menu.addItem(s)

        // ── Sprache ──
        let langSub = NSMenu()
        for lang in Language.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(doSetLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = (lang == Language.current) ? .on : .off
            langSub.addItem(item)
        }
        let langItem = NSMenuItem(title: Strings.languageMenu, action: nil, keyEquivalent: "")
        langItem.submenu = langSub
        menu.addItem(langItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Strings.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func addSection(_ iface: NetworkInterface, to menu: NSMenu) {
        let isCollapsed = collapsedInterfaces.contains(iface.serviceName)

        // ── Header ──
        let chevron = isCollapsed ? "▶" : "▼"
        let headerItem = NSMenuItem(title: "\(chevron) \(displayName(iface))",
                                    action: #selector(doToggleCollapse(_:)), keyEquivalent: "")
        headerItem.target = self
        headerItem.representedObject = iface.serviceName
        headerItem.attributedTitle = NSAttributedString(
            string: "\(chevron) \(displayName(iface))",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(headerItem)

        // ── Status (immer sichtbar) ──
        let (statusText, statusColor): (String, NSColor) = {
            if iface.isConnected { return (Strings.connected,     .systemGreen) }
            if iface.isEnabled   { return (Strings.disconnected,  .systemOrange) }
            return (Strings.disabledStatus, .secondaryLabelColor)
        }()
        let statusItem = NSMenuItem()
        statusItem.attributedTitle = NSAttributedString(string: statusText, attributes: [
            .foregroundColor: statusColor, .font: NSFont.systemFont(ofSize: 12)
        ])
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if isCollapsed { return }

        // ── Live-Geschwindigkeit ──
        if let spd = liveSpeed[iface.deviceName], iface.isConnected {
            menu.addItem(info("  ↓ \(fmtMbps(spd.down))  ↑ \(fmtMbps(spd.up))"))
        }

        menu.addItem(info("  Interface: \(iface.deviceName)"))

        if iface.isConnected {
            if let ip = iface.ipv4 {
                menu.addItem(copyItem("  IPv4:  \(ip)", value: ip))
                if let m = iface.subnet { menu.addItem(info("  \(Strings.subnet): \(m)")) }
            }
            if let ip6 = iface.ipv6  { menu.addItem(copyItem("  IPv6:  \(ip6)", value: ip6)) }
            if let gw  = iface.router { menu.addItem(copyItem("  Router: \(gw)", value: gw)) }
            if let sp  = iface.linkSpeed { menu.addItem(info("  \(Strings.linkSpeedLabel): \(sp)")) }
            if let rssi = iface.signalStrength {
                menu.addItem(info("  \(Strings.signalLabel): \(rssi) dBm (\(rssiLabel(rssi)))"))
            }
        }
        if let mac = iface.macAddress { menu.addItem(copyItem("  MAC:  \(mac)", value: mac)) }

        // ── Speedtest ──
        menu.addItem(.separator())
        switch speedStates[iface.deviceName] ?? .idle {
        case .idle:
            if iface.isConnected {
                let t = NSMenuItem(title: "  \(Strings.startTest)", action: #selector(doSpeedTest(_:)), keyEquivalent: "")
                t.target = self; t.representedObject = iface; menu.addItem(t)
            }
        case .running:
            menu.addItem(info("  \(Strings.testRunning)"))
        case .done(let result):
            menu.addItem(info("  \(result)"))
            if iface.isConnected {
                let retry = NSMenuItem(title: "  \(Strings.testRetry)", action: #selector(doSpeedTest(_:)), keyEquivalent: "")
                retry.target = self; retry.representedObject = iface; menu.addItem(retry)
            }
        }

        // ── Toggle ──
        menu.addItem(.separator())
        let lower = iface.serviceName.lowercased()
        let isIphone = lower.contains("iphone") || lower.contains("usb")
        let onOff = Strings.toggle(enabled: iface.isEnabled, isWifi: iface.type == .wifi, isIphone: isIphone)
        let toggle = NSMenuItem(title: onOff, action: #selector(doToggle(_:)), keyEquivalent: "")
        toggle.target = self; toggle.representedObject = iface; menu.addItem(toggle)
    }

    // MARK: - Display helpers

    private func displayName(_ iface: NetworkInterface) -> String {
        switch iface.type {
        case .wifi:
            return iface.ssid.map { "Wi-Fi – \($0)" } ?? "Wi-Fi"
        case .ethernet:
            let lower = iface.serviceName.lowercased()
            if lower.contains("iphone") || lower.contains("usb") { return "📱 \(iface.serviceName)" }
            return iface.serviceName
        }
    }

    private func fmtMbps(_ mbps: Double) -> String {
        if mbps < 0.01  { return "< 0.1 Mbps" }
        if mbps < 1     { return String(format: "%.2f Mbps", mbps) }
        if mbps < 1000  { return String(format: "%.1f Mbps", mbps) }
        return String(format: "%.2f Gbps", mbps / 1000)
    }

    private func rssiLabel(_ rssi: Int) -> String {
        switch rssi {
        case ...(-80):      return Strings.sigWeak
        case (-79)...(-60): return Strings.sigFair
        case (-59)...(-40): return Strings.sigGood
        default:            return Strings.sigExcellent
        }
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: title,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        item.isEnabled = false
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func copyItem(_ title: String, value: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(doCopy(_:)), keyEquivalent: "")
        item.target = self; item.representedObject = value
        item.toolTip = "Click to copy"
        return item
    }

    // MARK: - Actions

    @objc func doCopy(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(v, forType: .string)
        let orig = sender.title
        sender.title = "  \(Strings.copied)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sender.title = orig }
    }

    @objc func doToggleCollapse(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        if collapsedInterfaces.contains(name) { collapsedInterfaces.remove(name) }
        else { collapsedInterfaces.insert(name) }
        buildMenu()
    }

    @objc func doToggle(_ sender: NSMenuItem) {
        guard let iface = sender.representedObject as? NetworkInterface else { return }
        monitor.setEnabled(!iface.isEnabled, for: iface)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.refresh() }
    }

    @objc func doSpeedTest(_ sender: NSMenuItem) {
        guard let iface = sender.representedObject as? NetworkInterface else { return }
        speedStates[iface.deviceName] = .running
        buildMenu()
        monitor.speedTest(for: iface.deviceName) { [weak self] result in
            self?.speedStates[iface.deviceName] = .done(result)
            self?.buildMenu()
        }
    }

    @objc func doSetLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = Language(rawValue: raw) else { return }
        Language.current = lang
        buildMenu()
    }

    private func visibleServiceNames() -> [String] {
        let order = monitor.serviceOrder()
        return interfaces.sorted {
            (order.firstIndex(of: $0.serviceName) ?? 999) <
            (order.firstIndex(of: $1.serviceName) ?? 999)
        }.map { $0.serviceName }
    }

    @objc func doMoveUp(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        monitor.moveUp(name, visibleServices: visibleServiceNames())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
    }

    @objc func doMoveDown(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        monitor.moveDown(name, visibleServices: visibleServiceNames())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
    }

    @objc func doRefresh() { refresh() }

    @objc func doSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
            NSWorkspace.shared.open(url)
        }
    }
}
