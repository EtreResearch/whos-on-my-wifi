import Foundation

func cleanName(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    let host = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    guard !host.hasPrefix(";"), !host.lowercased().hasSuffix("in-addr.arpa"), ipv4(host) == nil, let label = host.split(separator: ".").first, !label.isEmpty,
          !label.allSatisfy(\.isNumber) else { return nil }
    return String(label)
}

func parseDig(_ output: String) -> String? {
    output.split(separator: "\n").lazy.compactMap { cleanName(String($0)) }.first
}

// Asks the router's DNS (DHCP hostnames), then the device's own mDNS responder (names phones and Macs announce).
// ponytail: unicast to the device, not 224.0.0.251 — multicast replies come from the device's address and dig drops them.
func nameQueries(_ ip: String, gateway: String?) -> [[String]] {
    (gateway.map { [["@" + $0]] } ?? []) + [["-p", "5353", "@" + ip]]
}

func lookupName(_ ip: String, gateway: String?) -> String? {
    for server in nameQueries(ip, gateway: gateway) {
        if let reply = try? runCommand("/usr/bin/dig", ["+short", "+time=1", "+tries=1", "-x", ip] + server, timeout: 3),
           reply.status == 0, let name = parseDig(reply.output) {
            return name
        }
    }
    return nil
}

func lookupNames(_ ips: [String], gateway: String?) -> [String: String] {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 32
    let lock = NSLock()
    var names: [String: String] = [:]
    for ip in ips {
        queue.addOperation {
            guard let name = lookupName(ip, gateway: gateway) else { return }
            lock.lock()
            names[ip] = name
            lock.unlock()
        }
    }
    queue.waitUntilAllOperationsAreFinished()
    return names
}

struct Sighting: Identifiable {
    let key: String
    let ip: String
    let mac: String?
    let name: String?
    let isLocal: Bool
    let firstSeen: Date
    let lastSeen: Date
    var id: String { key }
}

func sightingKey(_ device: Device) -> String { device.mac ?? device.ip }

func updateSightings(_ old: [String: Sighting], devices: [Device], names: [String: String], at date: Date) -> [String: Sighting] {
    var result = old
    for device in devices {
        let key = sightingKey(device)
        // A device first seen without a MAC was keyed by IP; carry its history over.
        let carried = key != device.ip && old[device.ip]?.mac == nil ? old[device.ip] : nil
        let previous = old[key] ?? carried
        if carried != nil { result[device.ip] = nil }
        result[key] = Sighting(key: key, ip: device.ip, mac: device.mac,
                               name: names[device.ip] ?? previous?.name, isLocal: device.isLocal,
                               firstSeen: previous?.firstSeen ?? date, lastSeen: date)
    }
    return result
}

func currentSightings(_ all: [String: Sighting], at date: Date) -> [Sighting] {
    all.values.filter { $0.lastSeen == date }.sorted {
        $0.firstSeen != $1.firstSeen ? $0.firstSeen > $1.firstSeen : (ipv4($0.ip) ?? 0) < (ipv4($1.ip) ?? 0)
    }
}
