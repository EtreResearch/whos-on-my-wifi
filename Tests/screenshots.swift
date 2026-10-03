// Renders README screenshots from made-up data. Run: sh screenshots.sh
import AppKit
import SwiftUI

let now = Date()
let home = try Network(interface: "en0", localIP: "192.168.1.23", mask: "255.255.255.0", gateway: "192.168.1.1")
let names: [(String?, Double)] = [("Priyas-iPhone", 95), ("Living-Room-TV", 300), ("Galaxy-S24", 41), (nil, 12),
                                  ("MacBook-Air", 180), (nil, 64), ("iPad", 7)]

func shot(_ model: Monitor, _ file: String, height: CGFloat) throws {
    let view = NSHostingView(rootView: Dashboard(model: model))
    view.frame = NSRect(x: 0, y: 0, width: 960, height: height)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = view
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
    print("Wrote \(file)")
}

_ = NSApplication.shared
let busy = Monitor()
busy.storageError = nil
var devices = [Device(ip: home.localIP, mac: nil, isLocal: true)]
var sightings = ["local": Sighting(key: "local", ip: home.localIP, mac: nil, name: nil, isLocal: true,
                                   firstSeen: now.addingTimeInterval(-3600), lastSeen: now)]
for (index, (name, minutes)) in names.enumerated() {
    let ip = "192.168.1.\(40 + index * 7)", mac = String(format: "0a:00:00:00:00:%02x", index + 1)
    devices.append(Device(ip: ip, mac: mac, isLocal: false))
    sightings[mac] = Sighting(key: mac, ip: ip, mac: mac, name: name, isLocal: false,
                              firstSeen: now.addingTimeInterval(-minutes * 60), lastSeen: now)
}
busy.result = ScanResult(network: home, devices: devices, date: now)
busy.sightings = sightings
busy.monitoring = true
busy.samples = stride(from: 86_000.0, through: 0, by: -600).map { ago in
    let hour = Calendar.current.component(.hour, from: now.addingTimeInterval(-ago))
    let base = [13, 14, 20, 21].contains(hour) ? 7 : [8, 9, 18, 19, 22].contains(hour) ? 5 : hour < 7 ? 2 : 3
    return CountSample(date: now.addingTimeInterval(-ago), network: home.label, count: base + (hour % 4 == 0 ? 1 : 0))
}
try shot(busy, "docs/screenshots/dashboard.png", height: 840)

let cafe = Monitor()
cafe.storageError = nil
cafe.result = ScanResult(network: home, devices: [devices[0]], date: now)
cafe.sightings = ["local": sightings["local"]!]
cafe.monitoring = true
cafe.samples = []
try shot(cafe, "docs/screenshots/public-wifi.png", height: 840)
