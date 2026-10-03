import Foundation

struct Device: Identifiable {
    let ip: String
    let mac: String?
    let isLocal: Bool
    var id: String { ip }
}

func ipv4(_ text: String) -> UInt32? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var result: UInt32 = 0
    for part in parts {
        guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let byte = UInt32(part), byte <= 255 else { return nil }
        result = (result << 8) | byte
    }
    return result
}

func address(_ value: UInt32) -> String {
    [24, 16, 8, 0].map { String((value >> $0) & 255) }.joined(separator: ".")
}

struct DiscoveryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Network: Equatable {
    let interface: String
    let localIP: String
    let gateway: String?
    let base: UInt32
    let broadcast: UInt32
    let prefix: Int
    var label: String { "\(address(base))/\(prefix)" }
    let totalHosts: Int
    let firstHost: UInt32
    let lastHost: UInt32
    var hosts: [String] { (firstHost...lastHost).map(address) }
    var isPartial: Bool { Int(lastHost - firstHost) + 1 < totalHosts }

    init(interface: String, localIP: String, mask: String, gateway: String?) throws {
        guard interface.range(of: "^en[0-9]+$", options: .regularExpression) != nil,
              let ip = ipv4(localIP), let bits = ipv4(mask),
              (~bits & ((~bits) &+ 1)) == 0 else {
            throw DiscoveryError(message: "Could not read a valid Wi-Fi IPv4 address and subnet mask.")
        }
        let size = UInt64(~bits) + 1
        guard bits.nonzeroBitCount >= 8, size >= 4 else {
            throw DiscoveryError(message: "This Wi-Fi subnet has no discoverable host range.")
        }
        base = ip & bits
        broadcast = base | ~bits
        totalHosts = Int(size) - 2
        // ponytail: large networks get the 1,024-address block around this Mac; the rest is unscanned and labelled so.
        let block = ip & ~UInt32(1023)
        firstHost = size > 1024 ? max(base + 1, block) : base + 1
        lastHost = size > 1024 ? min(broadcast - 1, block + 1023) : broadcast - 1
        guard ip > base, ip < broadcast, ip >> 24 != 127, ip >> 24 < 224, ip >> 24 != 0 else {
            throw DiscoveryError(message: "Wi-Fi has an invalid host address. Reconnect and try again.")
        }
        self.interface = interface
        self.localIP = localIP
        if let gateway, let number = ipv4(gateway), number > base, number < broadcast {
            self.gateway = gateway
        } else {
            self.gateway = nil
        }
        prefix = bits.nonzeroBitCount
    }

    func contains(_ ip: String) -> Bool {
        guard let number = ipv4(ip) else { return false }
        return number > base && number < broadcast
    }
}

func normalizedMAC(_ value: String) -> String? {
    let bytes = value.split(separator: ":", omittingEmptySubsequences: false)
    guard bytes.count == 6 else { return nil }
    let numbers = bytes.compactMap { byte -> UInt8? in
        guard (1...2).contains(byte.count), byte.allSatisfy(\.isHexDigit) else { return nil }
        return UInt8(byte, radix: 16)
    }
    guard numbers.count == 6, numbers[0] & 1 == 0, numbers.contains(where: { $0 != 0 }) else { return nil }
    return numbers.map { String(format: "%02x", $0) }.joined(separator: ":")
}

func makeDevices(localIP: String, gateway: String?, responses: Set<String>, cache: String,
                 interface: String, contains: (String) -> Bool) -> [Device] {
    var macs: [String: String] = [:]
    for line in cache.split(separator: "\n") {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 6, parts[2] == "at", parts[4] == "on", parts[5] == interface,
              parts[1].hasPrefix("("), parts[1].hasSuffix(")"),
              let mac = normalizedMAC(parts[3]) else { continue }
        let ip = String(parts[1].dropFirst().dropLast())
        if contains(ip) { macs[ip] = mac }
    }
    // The neighbor cache only supplies MAC addresses; a cache entry alone never means a device is online.
    let candidates = responses.union([localIP]).filter {
        $0 != gateway && contains($0)
    }.map {
        Device(ip: $0, mac: macs[$0], isLocal: $0 == localIP)
    }.sorted {
        $0.isLocal != $1.isLocal ? $0.isLocal : (ipv4($0.ip) ?? 0) < (ipv4($1.ip) ?? 0)
    }
    var seen = Set<String>()
    return candidates.filter { seen.insert($0.mac ?? $0.ip).inserted }
}

func runCommand(_ executable: String, _ arguments: [String], timeout: Double = 4) throws -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let deadline = DispatchWorkItem {
        if process.isRunning { process.terminate() }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    deadline.cancel()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func readNetwork() throws -> Network {
    let ports = try runCommand("/usr/sbin/networksetup", ["-listallhardwareports"])
    guard ports.status == 0 else {
        throw DiscoveryError(message: "macOS could not list network interfaces. Check your network settings and try again.")
    }
    let lines = ports.output.components(separatedBy: .newlines)
    for (index, line) in lines.enumerated() where line == "Hardware Port: Wi-Fi" || line == "Hardware Port: AirPort" {
        guard index + 1 < lines.count, lines[index + 1].hasPrefix("Device: ") else { continue }
        let interface = String(lines[index + 1].dropFirst(8))
        guard interface.range(of: "^en[0-9]+$", options: .regularExpression) != nil else { continue }
        let ip = try runCommand("/usr/sbin/ipconfig", ["getifaddr", interface])
        guard ip.status == 0, ipv4(ip.output) != nil else { continue }
        let config = try runCommand("/sbin/ifconfig", [interface])
        let words = config.output.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let index = words.firstIndex(of: ip.output), index + 2 < words.count,
              words[index + 1] == "netmask", words[index + 2].hasPrefix("0x"),
              let mask = UInt32(words[index + 2].dropFirst(2), radix: 16) else {
            throw DiscoveryError(message: "Could not read the Wi-Fi subnet mask. Reconnect Wi-Fi and try again.")
        }
        let route = try runCommand("/sbin/route", ["-n", "get", "-ifscope", interface, "default"])
        let gateway = route.output.components(separatedBy: .newlines).compactMap { line -> String? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.count == 2 && parts[0] == "gateway:" ? String(parts[1]) : nil
        }.first
        return try Network(interface: interface, localIP: ip.output, mask: address(mask), gateway: gateway)
    }
    throw DiscoveryError(message: "Connect this Mac to your Wi-Fi, then scan again. An IPv4 Wi-Fi connection is required.")
}

struct ScanResult {
    let network: Network
    let devices: [Device]
    let date: Date
    var respondingCount: Int { devices.count }
    var isHiddenNetwork: Bool { respondingCount == 1 && !network.isPartial }
}

func probeWasBlocked(_ output: String) -> Bool {
    let message = output.lowercased()
    return ["permission denied", "operation not permitted", "no route to host",
            "network is unreachable", "can't assign requested address"].contains { message.contains($0) }
}

func scanNetwork() throws -> ScanResult {
    let network = try readNetwork()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 32
    let lock = NSLock()
    var responses = Set<String>()
    var launchFailed = false
    var blockedProbes = 0
    let targets = network.hosts.filter { $0 != network.localIP }
    for ip in targets {
        queue.addOperation {
            do {
                let reply = try runCommand("/sbin/ping", ["-n", "-q", "-c", "1", "-W", "700", "-t", "1", "-b", network.interface, "-S", network.localIP, ip], timeout: 2)
                if reply.status == 0 {
                    lock.lock()
                    responses.insert(ip)
                    lock.unlock()
                } else if probeWasBlocked(reply.output) {
                    lock.lock()
                    blockedProbes += 1
                    lock.unlock()
                }
            } catch {
                lock.lock()
                launchFailed = true
                lock.unlock()
            }
        }
    }
    queue.waitUntilAllOperationsAreFinished()
    guard !launchFailed else {
        throw DiscoveryError(message: "macOS could not start network probes. Close other apps and try again.")
    }
    guard blockedProbes != targets.count else {
        throw DiscoveryError(message: "Network probes were blocked by permission or routing errors. Allow Who's on My Wi-Fi in System Settings → Privacy & Security → Local Network, check your Wi-Fi connection, and try again.")
    }
    let cache = try runCommand("/usr/sbin/arp", ["-an", "-i", network.interface])
    guard cache.status == 0 else {
        throw DiscoveryError(message: "Could not read the local device cache. Check Local Network permission in System Settings and try again.")
    }
    guard try readNetwork() == network else {
        throw DiscoveryError(message: "The Wi-Fi connection changed during the scan. Try again.")
    }
    let devices = makeDevices(localIP: network.localIP, gateway: network.gateway, responses: responses,
                              cache: cache.output, interface: network.interface, contains: network.contains)
    return ScanResult(network: network, devices: devices, date: Date())
}
