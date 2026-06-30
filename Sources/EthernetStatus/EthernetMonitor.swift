import Foundation

enum InterfaceType { case ethernet, wifi }

struct NetworkInterface {
    let type: InterfaceType
    let serviceName: String
    let deviceName: String
    let isEnabled: Bool
    let isConnected: Bool
    let ipv4: String?
    let ipv6: String?
    let macAddress: String?
    let linkSpeed: String?
    let subnet: String?
    let router: String?
    let ssid: String?         // WiFi only
    let signalStrength: Int?  // WiFi only, dBm
}

class NetworkMonitor {

    private func run(_ cmd: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", cmd]
        guard (try? task.run()) != nil else { return "" }
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Fetch All Interfaces

    func fetchInterfaces() -> [NetworkInterface] {
        // Build device → actual service name map from -listnetworkserviceorder
        var deviceToService: [String: String] = [:]
        var currentService: String?
        for line in run("networksetup -listnetworkserviceorder").components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("("), !t.hasPrefix("(Hardware"), let r = t.range(of: ") ") {
                var name = String(t[r.upperBound...])
                if name.hasPrefix("* ") { name = String(name.dropFirst(2)) }
                currentService = name
            } else if t.hasPrefix("(Hardware Port:"), let svc = currentService,
                      let devRange = t.range(of: "Device: ") {
                var dev = String(t[devRange.upperBound...])
                if dev.hasSuffix(")") { dev = String(dev.dropLast()) }
                dev = dev.trimmingCharacters(in: .whitespaces)
                if !dev.isEmpty { deviceToService[dev] = svc }
            }
        }

        var result: [NetworkInterface] = []
        for block in run("networksetup -listallhardwareports").components(separatedBy: "\n\n") {
            var portName: String?
            var device: String?
            for line in block.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("Hardware Port: ") { portName = String(t.dropFirst(15)) }
                else if t.hasPrefix("Device: ")    { device   = String(t.dropFirst(8)) }
            }
            guard let port = portName, let dev = device else { continue }
            let lower = port.lowercased()
            if ["bluetooth", "thunderbolt bridge", "vpn", "loopback", "firewire"]
                .contains(where: { lower.contains($0) }) { continue }

            // Use actual service name (e.g. "LAN MAC"), fall back to hardware port name
            let serviceName = deviceToService[dev] ?? port

            if lower.contains("wi-fi") || lower.contains("wifi") {
                if let i = buildWiFi(serviceName, dev) { result.append(i) }
            } else {
                if let i = buildEthernet(serviceName, dev) { result.append(i) }
            }
        }
        return result
    }

    // MARK: - Ethernet

    private func buildEthernet(_ service: String, _ device: String) -> NetworkInterface? {
        let enabled = isServiceEnabled(service)
        let verbose = run("ifconfig -v \(device) 2>/dev/null")
        guard !verbose.isEmpty, isRealEthernet(verbose, name: service) else { return nil }

        let connected = verbose.contains("status: active")
        let mac = extractMAC(verbose)

        // Filter virtual adapters (locally-administered MAC) when disconnected
        if !connected, let m = mac, isLocallyAdmin(m) { return nil }

        let (ipv4, subnet, ipv6) = parseIPs(verbose)
        let router = parseRouter(service)
        let speed = parseLinkSpeed(verbose)

        return NetworkInterface(type: .ethernet, serviceName: service, deviceName: device,
            isEnabled: enabled, isConnected: connected,
            ipv4: ipv4, ipv6: ipv6, macAddress: mac,
            linkSpeed: speed, subnet: subnet, router: router,
            ssid: nil, signalStrength: nil)
    }

    // MARK: - WiFi

    private let airportBin = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

    private func buildWiFi(_ service: String, _ device: String) -> NetworkInterface? {
        let enabled = isServiceEnabled(service)
        let verbose = run("ifconfig -v \(device) 2>/dev/null")
        guard !verbose.isEmpty else { return nil }

        let connected = verbose.contains("status: active")
        let mac = extractMAC(verbose)
        let (ipv4, subnet, ipv6) = parseIPs(verbose)
        let router = parseRouter(service)

        // SSID
        var ssid: String?
        let ssidOut = run("networksetup -getairportnetwork \(device) 2>/dev/null")
        if ssidOut.contains("Current Wi-Fi Network:") {
            ssid = ssidOut.replacingOccurrences(of: "Current Wi-Fi Network:", with: "")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Signal strength + link speed via airport
        var rssi: Int?
        var linkSpeed: String?
        for line in run("\(airportBin) -I 2>/dev/null").components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("agrCtlRSSI:") {
                rssi = Int(t.dropFirst(11).trimmingCharacters(in: .whitespaces))
            } else if t.hasPrefix("lastTxRate:") {
                let r = t.dropFirst(11).trimmingCharacters(in: .whitespaces)
                if r != "0" && !r.isEmpty { linkSpeed = "\(r) Mbps" }
            }
        }

        return NetworkInterface(type: .wifi, serviceName: service, deviceName: device,
            isEnabled: enabled, isConnected: connected,
            ipv4: ipv4, ipv6: ipv6, macAddress: mac,
            linkSpeed: linkSpeed, subnet: subnet, router: router,
            ssid: ssid, signalStrength: rssi)
    }

    // MARK: - Service Order

    func serviceOrder() -> [String] {
        var order: [String] = []
        for line in run("networksetup -listnetworkserviceorder").components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("("), !t.hasPrefix("(Hardware"),
                  let closeRange = t.range(of: ") ") else { continue }
            var name = String(t[closeRange.upperBound...])
            if name.hasPrefix("* ") { name = String(name.dropFirst(2)) }
            if !name.isEmpty { order.append(name) }
        }
        return order
    }

    func moveUp(_ service: String, visibleServices: [String]) {
        guard let visIdx = visibleServices.firstIndex(of: service), visIdx > 0 else { return }
        swapInOrder(service, visibleServices[visIdx - 1])
    }

    func moveDown(_ service: String, visibleServices: [String]) {
        guard let visIdx = visibleServices.firstIndex(of: service), visIdx < visibleServices.count - 1 else { return }
        swapInOrder(service, visibleServices[visIdx + 1])
    }

    private func swapInOrder(_ a: String, _ b: String) {
        var order = serviceOrder()
        guard let ia = order.firstIndex(of: a), let ib = order.firstIndex(of: b) else { return }
        order.swapAt(ia, ib)
        let args = order.map { "'\(esc($0))'" }.joined(separator: " ")
        osascript("do shell script \"networksetup -ordernetworkservices \(args)\" with administrator privileges")
    }

    // MARK: - Live Throughput (netstat sampling)

    func netstatBytes(for device: String) -> (rx: UInt64, tx: UInt64)? {
        let out = run("netstat -I \(device) -b 2>/dev/null")
        for line in out.components(separatedBy: "\n") {
            let p = line.split(separator: " ", omittingEmptySubsequences: true)
            guard p.count >= 10, String(p[0]) == device,
                  let rx = UInt64(String(p[6])), let tx = UInt64(String(p[9])) else { continue }
            return (rx, tx)
        }
        return nil
    }

    // MARK: - Speed Test (networkQuality, macOS 12+)

    func speedTest(for device: String, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Try without -s first (more info), fallback to -s
            let out = self.run("networkQuality -I \(device) 2>&1")
            DispatchQueue.main.async { completion(self.parseSpeedTest(out)) }
        }
    }

    private func parseSpeedTest(_ output: String) -> String {
        let lower = output.lowercased()
        if lower.contains("command not found") || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Strings.testUnavailable
        }
        var dl: String?
        var ul: String?
        var latency: String?

        for line in output.components(separatedBy: "\n") {
            let ll = line.lowercased()
            // networkQuality uses "Uplink capacity" / "Downlink capacity"
            if ll.contains("downlink") || (ll.contains("download") && ll.contains("capacity")) {
                dl = dl ?? extractSpeed(line)
            } else if ll.contains("uplink") || (ll.contains("upload") && ll.contains("capacity")) {
                ul = ul ?? extractSpeed(line)
            } else if ll.contains("idle latency") || ll.contains("latency:") {
                if let r = line.range(of: #"[\d.]+\s*ms"#, options: .regularExpression) {
                    latency = String(line[r])
                }
            } else if ll.contains("responsiveness") {
                // "Responsiveness: High (982 RPM)" → extract RPM as proxy for latency
                if latency == nil, let r = line.range(of: #"\d+\s*RPM"#, options: .regularExpression) {
                    latency = String(line[r])
                }
            }
        }
        var parts: [String] = []
        if let d = dl { parts.append("↓ \(d)") }
        if let u = ul { parts.append("↑ \(u)") }
        if let l = latency { parts.append("🏓 \(l)") }
        return parts.isEmpty ? Strings.testFailed : parts.joined(separator: "  ")
    }

    private func extractSpeed(_ line: String) -> String? {
        // Matches "219.946 Mbps", "94.9 Mbps", "1.2 Gbps", "512 Kbps"
        guard let r = line.range(of: #"[\d.]+\s*[KMGk][Bb]ps"#, options: .regularExpression) else { return nil }
        return String(line[r])
    }

    // MARK: - Toggle

    func setEnabled(_ enabled: Bool, for iface: NetworkInterface) {
        let action = enabled ? "on" : "off"
        let e = esc(iface.serviceName).replacingOccurrences(of: "'", with: "\\'")
        osascript("do shell script \"networksetup -setnetworkserviceenabled '\(e)' \(action)\" with administrator privileges")
    }

    // MARK: - Private Helpers

    private func isServiceEnabled(_ service: String) -> Bool {
        run("networksetup -getnetworkserviceenabled '\(esc(service))' 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "enabled"
    }

    private func isRealEthernet(_ verbose: String, name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("ethernet") || lower.contains("lan") { return true }
        for line in verbose.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("media:") {
                return t.contains("none") || (t.contains("(") && t.contains(")"))
            }
        }
        return false
    }

    private func isLocallyAdmin(_ mac: String) -> Bool {
        guard let first = mac.components(separatedBy: ":").first,
              let byte = UInt8(first, radix: 16) else { return false }
        return (byte & 0x02) != 0
    }

    private func extractMAC(_ ifcfg: String) -> String? {
        for line in ifcfg.components(separatedBy: "\n") {
            let p = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            if p.first == "ether" && p.count >= 2 { return p[1] }
        }
        return nil
    }

    private func parseIPs(_ ifcfg: String) -> (ipv4: String?, subnet: String?, ipv6: String?) {
        var ipv4, subnet, ipv6: String?
        for line in ifcfg.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            switch parts.first {
            case "inet":
                if parts.count >= 2 { ipv4 = parts[1] }
                if let i = parts.firstIndex(of: "netmask"), i + 1 < parts.count {
                    subnet = hexToNetmask(parts[i + 1])
                }
            case "inet6":
                if parts.count >= 2 {
                    let a = parts[1].components(separatedBy: "%").first ?? parts[1]
                    if !a.hasPrefix("fe80") && ipv6 == nil { ipv6 = a }
                }
            default: break
            }
        }
        return (ipv4, subnet, ipv6)
    }

    private func parseRouter(_ service: String) -> String? {
        for line in run("networksetup -getinfo '\(esc(service))' 2>/dev/null").components(separatedBy: "\n") {
            if line.hasPrefix("Router:") {
                let r = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
                if !r.isEmpty && r != "none" { return r }
            }
        }
        return nil
    }

    private func parseLinkSpeed(_ ifcfg: String) -> String? {
        for line in ifcfg.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("link rate:") {
                return String(t.dropFirst(10)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func hexToNetmask(_ hex: String) -> String? {
        let c = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard c.count == 8, let v = UInt32(c, radix: 16) else { return nil }
        return [24, 16, 8, 0].map { String((v >> $0) & 0xFF) }.joined(separator: ".")
    }

    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "'", with: "'\\''") }

    private func osascript(_ script: String) {
        let t = Process()
        t.launchPath = "/usr/bin/osascript"
        t.arguments = ["-e", script]
        try? t.run()
    }
}
