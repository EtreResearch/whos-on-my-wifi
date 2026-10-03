import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let cache = """
? (192.168.1.1) at aa:bb:cc:dd:ee:01 on en0 ifscope [ethernet]
? (192.168.1.3) at a:b:c:d:e:f on en0 ifscope [ethernet]
? (192.168.1.4) at aa:bb:cc:dd:ee:04 on en0 ifscope [ethernet]
? (192.168.1.5) at (incomplete) on en0 ifscope [ethernet]
? (192.168.1.6) at aa:bb:cc:dd:ee:06 on en1 ifscope [ethernet]
? (192.168.1.7) at 0a:0b:0c:0d:0e:0f on en0 ifscope [ethernet]
? (192.168.1.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
? (224.0.0.1) at 1:0:5e:0:0:1 on en0 ifscope [ethernet]
? (10.0.0.8) at aa:bb:cc:dd:ee:08 on en0 ifscope [ethernet]
"""

let devices = makeDevices(localIP: "192.168.1.2", gateway: "192.168.1.1",
    responses: ["192.168.1.1", "192.168.1.3", "192.168.1.7"], cache: cache,
    interface: "en0", contains: { $0.hasPrefix("192.168.1.") && $0 != "192.168.1.255" })
check(devices.count == 2, "count self and one responding device, not gateway, duplicates, or cache-only devices")
check(devices.first(where: { $0.isLocal })?.ip == "192.168.1.2", "include this Mac")
check(devices.first(where: { $0.ip == "192.168.1.3" })?.mac == "0a:0b:0c:0d:0e:0f", "normalize macOS short MAC bytes")
check(!devices.contains { $0.ip == "192.168.1.4" }, "a cache-only device is not online")
let network = try Network(interface: "en0", localIP: "192.168.1.130", mask: "255.255.255.128", gateway: "192.168.1.129")
check(network.hosts.count == 126 && network.hosts.first == "192.168.1.129" && network.hosts.last == "192.168.1.254", "respect real subnet mask, not an assumed /24")
check(!network.contains("192.168.1.128") && !network.contains("192.168.1.255") && !network.contains("192.168.1.127"), "exclude network, broadcast, and adjacent subnet")
check(network.label == "192.168.1.128/25", "identify the current subnet")
for mask in ["255.0.255.0", "0.0.0.0", "128.0.0.0", "255.255.255.255", "255.255.255.254"] {
    check((try? Network(interface: "en0", localIP: "192.168.1.2", mask: mask, gateway: nil)) == nil, "reject invalid or unsuitable mask \(mask)")
}
for ip in ["1.2.3", "1.2.3.256", "-1.2.3.4", "1..3.4", "1.2.3.4\n"] {
    check(ipv4(ip) == nil, "reject malformed IP \(ip)")
}
check((try? Network(interface: "en0; echo bad", localIP: "192.168.1.2", mask: "255.255.255.0", gateway: nil)) == nil, "reject an invalid interface")
check(normalizedMAC("ff:ff:ff:ff:ff:ff") == nil && normalizedMAC("0:0:0:0:0:0") == nil, "reject broadcast and empty MAC addresses")
let uncached = makeDevices(localIP: "192.168.1.130", gateway: nil, responses: ["192.168.1.131", "10.0.0.1"], cache: "", interface: "en0", contains: network.contains)
check(uncached.count == 2, "include a responder without ARP and reject a response outside the subnet")
let started = Date()
let timed = try runCommand("/bin/sleep", ["5"], timeout: 0.1)
check(timed.status != 0 && Date().timeIntervalSince(started) < 2, "terminate stalled child processes")
let output = try runCommand("/usr/bin/printf", ["%s", "safe;$(text)"])
check(output.status == 0 && output.output == "safe;$(text)", "pass arguments literally without a shell")
let failureOutput = try runCommand("/bin/ls", ["/nonexistent-wifi-monitor-check"])
check(failureOutput.status != 0 && !failureOutput.output.isEmpty, "preserve command errors so a blocked scan is not counted as success")
check(probeWasBlocked("ping: sendto: No route to host") && probeWasBlocked("Operation not permitted"), "recognize macOS routing and permission errors")
check(!probeWasBlocked("1 packets transmitted, 0 packets received, 100.0% packet loss"), "normal unanswered probes are not permission failures")

let now = Date(timeIntervalSince1970: 1_800_000_000)
let samples = [CountSample(date: now.addingTimeInterval(-86401), network: "old", count: 9),
               CountSample(date: now.addingTimeInterval(-60), network: "current", count: 2),
               CountSample(date: now.addingTimeInterval(30), network: "future", count: 9),
               CountSample(date: now, network: "current", count: 3)]
let recent = recentSamples(samples, now: now)
check(recent.map(\.count) == [2, 3], "discard expired and future samples, preserving successful counts in order")
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: folder) }
let file = folder.appendingPathComponent("history.json")
let missingHistory = try loadHistory(from: file, now: now)
check(missingHistory.isEmpty, "start with empty history when no file exists")
try saveHistory(recent, to: file)
let loadedHistory = try loadHistory(from: file, now: now)
check(loadedHistory.map(\.count) == [2, 3], "round-trip aggregate history")
try Data("corrupt".utf8).write(to: file)
check((try? loadHistory(from: file, now: now)) == nil, "report corrupt history rather than silently treating it as empty")
check(cleanName("Rahuls-iPhone.local.") == "Rahuls-iPhone", "strip mDNS suffix and trailing dot")
check(cleanName("android-5f2a.lan") == "android-5f2a", "strip router domain suffix")
check(cleanName("Office-PC") == "Office-PC", "keep a bare hostname")
check(cleanName("192.168.1.5") == nil && cleanName("5.1.168.192.in-addr.arpa.") == nil, "reject IP-shaped answers")
check(cleanName("5.1.168.192.IN-ADDR.ARPA") == nil && cleanName("") == nil && cleanName("  ") == nil, "reject empty names")
check(parseDig(";; connection timed out; no servers could be reached") == nil, "dig timeout is no name")
check(parseDig("\nMeera-MacBook.local.\nother.local.") == "Meera-MacBook", "use the first answer")
check(parseDig("") == nil, "empty dig output is no name")
let t1 = Date(timeIntervalSince1970: 1_800_000_000), t2 = t1.addingTimeInterval(60), t3 = t2.addingTimeInterval(60)
let phone = Device(ip: "192.168.1.10", mac: nil, isLocal: false)
let phoneWithMAC = Device(ip: "192.168.1.10", mac: "0a:00:00:00:00:10", isLocal: false)
let laptop = Device(ip: "192.168.1.11", mac: "0a:00:00:00:00:11", isLocal: false)
var seen = updateSightings([:], devices: [phone, laptop], names: ["192.168.1.10": "Rahuls-iPhone"], at: t1)
check(seen.count == 2, "each device is sighted once")
seen = updateSightings(seen, devices: [phoneWithMAC], names: [:], at: t2)
check(currentSightings(seen, at: t2).map(\.key) == ["0a:00:00:00:00:10"], "only latest-scan devices are current; a gained MAC replaces the IP key")
check(seen["0a:00:00:00:00:10"]?.firstSeen == t1 && seen["0a:00:00:00:00:10"]?.name == "Rahuls-iPhone", "a gained MAC keeps first-seen and name")
seen = updateSightings(seen, devices: [phoneWithMAC, laptop], names: [:], at: t3)
let laptopNow = seen["0a:00:00:00:00:11"]
check(laptopNow?.firstSeen == t1 && laptopNow?.lastSeen == t3, "a returning device keeps its first-seen time")
check(currentSightings(seen, at: t3).count == 2, "returning device is current again")
check(seen["0a:00:00:00:00:10"]?.name == "Rahuls-iPhone", "a skipped lookup keeps the earlier name")
check(nameQueries("192.168.1.20", gateway: "192.168.1.1") == [["@192.168.1.1"], ["-p", "5353", "@192.168.1.20"]], "ask the router, then the device itself over mDNS (multicast replies come from the device and dig rejects them)")
check(nameQueries("192.168.1.20", gateway: nil) == [["-p", "5353", "@192.168.1.20"]], "without a router, ask the device only")
let big = try Network(interface: "en0", localIP: "10.20.37.5", mask: "255.255.0.0", gateway: "10.20.0.1")
check(big.isPartial && big.hosts.count == 1024 && big.hosts.first == "10.20.36.0" && big.hosts.last == "10.20.39.255", "scan the 1,024-address block around this Mac")
check(big.totalHosts == 65534 && big.contains("10.20.200.1"), "the whole subnet still bounds accepted devices")
let low = try Network(interface: "en0", localIP: "10.20.0.9", mask: "255.255.0.0", gateway: nil)
check(low.hosts.first == "10.20.0.1" && low.hosts.count == 1023, "never probe the network address")
let high = try Network(interface: "en0", localIP: "10.20.255.9", mask: "255.255.0.0", gateway: nil)
check(high.hosts.last == "10.20.255.254" && high.hosts.count == 1023, "never probe the broadcast address")
let exact = try Network(interface: "en0", localIP: "192.168.4.9", mask: "255.255.252.0", gateway: nil)
check(!exact.isPartial && exact.hosts.count == 1022, "a 1,024-address subnet is scanned fully")
let huge = try Network(interface: "en0", localIP: "10.1.2.3", mask: "255.0.0.0", gateway: nil)
check(huge.isPartial && huge.hosts.count == 1024 && huge.totalHosts == 16_777_214, "a /8 gets a partial scan")
let outside = makeDevices(localIP: "10.20.37.5", gateway: nil, responses: [], cache: "? (10.20.200.1) at aa:bb:cc:dd:ee:20 on en0 ifscope [ethernet]", interface: "en0", contains: big.contains)
check(outside.count == 1, "cache entries outside the scanned block are never counted")
check(!network.isPartial, "small subnets are not partial")
check(ScanResult(network: network, devices: makeDevices(localIP: "192.168.1.130", gateway: nil, responses: [], cache: "", interface: "en0", contains: network.contains), date: Date()).isHiddenNetwork, "only this Mac visible means a hidden network")
check(!ScanResult(network: network, devices: uncached, date: Date()).isHiddenNetwork, "another responder means not hidden")
check(!ScanResult(network: big, devices: makeDevices(localIP: "10.20.37.5", gateway: nil, responses: [], cache: "", interface: "en0", contains: big.contains), date: Date()).isHiddenNetwork, "an empty block of a partial scan is not proof the network hides devices")
print("PASS: discovery, subnet validation, process deadlines, and history persistence")
if CommandLine.arguments.contains("--live") {
    do {
        let scan = try scanNetwork()
        print("LIVE: \(scan.network.label), \(scan.respondingCount) responding (including this Mac); router identified: \(scan.network.gateway != nil)")
        let names = lookupNames(scan.devices.filter { !$0.isLocal }.map(\.ip), gateway: scan.network.gateway)
        print("LIVE: \(names.count) of \(scan.respondingCount - 1) other devices named: \(names.values.sorted().joined(separator: ", "))")
    } catch {
        fputs("LIVE ERROR: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
