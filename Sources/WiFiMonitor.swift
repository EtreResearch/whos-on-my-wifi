import SwiftUI
import Charts

final class Monitor: ObservableObject {
    @Published var result: ScanResult?
    @Published var scanning = false
    @Published var monitoring = false
    @Published var scanError: String?
    @Published var storageError: String?
    @Published var samples: [CountSample] = []
    @Published var sightings: [String: Sighting] = [:]
    private var timer: Timer?
    private var canSave = true
    private let historyFile: URL

    init() {
        historyFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Whos On My WiFi/history.json")
        do {
            samples = try loadHistory(from: historyFile)
        } catch {
            canSave = false
            storageError = "Saved history could not be read. New counts will stay in memory; the original file has been preserved."
        }
    }

    var currentSamples: [CountSample] {
        guard let network = result?.network.label else { return [] }
        return recentSamples(samples, now: Date()).filter { $0.network == network }
    }

    var currentDevices: [Sighting] {
        result.map { currentSightings(sightings, at: $0.date) } ?? []
    }

    func setMonitoring(_ enabled: Bool) {
        monitoring = enabled
        timer?.invalidate()
        timer = nil
        if enabled {
            scan()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.scan() }
        }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        scanError = nil
        let named = Set(sightings.filter { $0.value.name != nil }.keys)
        DispatchQueue.global(qos: .utility).async {
            let outcome = Result { () throws -> (ScanResult, [String: String]) in
                let scan = try scanNetwork()
                let unnamed = scan.devices.filter { !$0.isLocal && !named.contains(sightingKey($0)) }
                return (scan, lookupNames(unnamed.map(\.ip), gateway: scan.network.gateway))
            }
            DispatchQueue.main.async {
                self.scanning = false
                switch outcome {
                case .success(let (scan, names)):
                    self.result = scan
                    self.sightings = updateSightings(self.sightings, devices: scan.devices, names: names, at: scan.date)
                    self.samples = recentSamples(self.samples + [CountSample(date: scan.date, network: scan.network.label,
                                                                           count: scan.respondingCount)], now: scan.date)
                    if self.canSave {
                        do {
                            try saveHistory(self.samples, to: self.historyFile)
                            self.storageError = nil
                        } catch {
                            self.storageError = "Could not save history to this Mac. Counts are available for this session only."
                        }
                    }
                case .failure(let error):
                    self.scanError = error.localizedDescription
                }
            }
        }
    }

    func showHistory() {
        NSWorkspace.shared.open(historyFile.deletingLastPathComponent())
    }
}

struct Dashboard: View {
    @ObservedObject var model: Monitor
    private let accent = Color(red: 0.04, green: 0.46, blue: 0.40)

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "wifi")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 54, height: 54)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Who's on My Wi-Fi").font(.system(size: 27, weight: .bold))
                    Text("Devices sharing this Wi-Fi").foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.scan) {
                    Label(model.scanning ? "Scanning…" : "Refresh now", systemImage: "arrow.clockwise")
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.scanning)
                .keyboardShortcut("r", modifiers: .command)
            }

            HStack {
                Circle().fill(model.monitoring ? accent : Color.secondary).frame(width: 7, height: 7)
                Text(model.monitoring ? "Updating every minute" : "Auto-refresh is off")
                Spacer()
                Toggle("Auto-refresh every minute", isOn: Binding(get: { model.monitoring }, set: model.setMonitoring))
                    .toggleStyle(.switch).controlSize(.small)
            }
            .font(.callout)

            HStack(spacing: 14) {
                metric(model.result.map { String($0.respondingCount) } ?? "—", "Devices on your Wi-Fi right now",
                       model.result.map { "Updated \($0.date.formatted(date: .omitted, time: .shortened)) · includes this Mac" } ?? "Waiting for the first scan",
                       color: accent)
                metric(model.currentSamples.map(\.count).max().map(String.init) ?? "—", "Busiest in 24 hours",
                       "Most devices seen at once", color: .primary)
            }

            if let error = model.scanError {
                notice(error + (model.result == nil ? "" : " Showing the last successful scan below."), symbol: "exclamationmark.triangle", color: .orange)
            }
            if let error = model.storageError {
                notice(error, symbol: "externaldrive.badge.exclamationmark", color: .orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Busy hours").font(.headline)
                    Spacer()
                    Text("Last 24 hours · stored on this Mac").font(.caption).foregroundStyle(.secondary)
                }
                if model.currentSamples.isEmpty {
                    Text("Successful scans will appear here. Turn on Auto-refresh to track changes.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 85)
                } else {
                    Chart(model.currentSamples) { sample in
                        LineMark(x: .value("Time", sample.date), y: .value("Responding devices", sample.count))
                            .foregroundStyle(accent).interpolationMethod(.stepEnd)
                        PointMark(x: .value("Time", sample.date), y: .value("Responding devices", sample.count))
                            .foregroundStyle(accent).symbolSize(14)
                    }
                    .chartYScale(domain: 0...max(5, (model.currentSamples.map(\.count).max() ?? 0) + 1))
                    .frame(height: 100)
                    .accessibilityLabel("Responding device counts from successful scans on this subnet")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Devices").font(.headline)
                    Spacer()
                    if model.scanning { ProgressView().controlSize(.small) }
                    if let result = model.result {
                        Text("\(result.network.label) · \(result.network.interface)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                if let result = model.result {
                    Table(model.currentDevices) {
                        TableColumn("Device") { device in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(device.isLocal ? "This Mac" : device.name ?? "Unknown device",
                                      systemImage: device.isLocal ? "laptopcomputer" : device.name == nil ? "questionmark.circle" : "laptopcomputer.and.iphone")
                                Text([device.ip, device.mac].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }.width(min: 260, ideal: 340)
                        TableColumn("First seen") { device in
                            Text(device.firstSeen.formatted(date: .omitted, time: .shortened))
                        }.width(min: 90, ideal: 110)
                        TableColumn("Last seen") { device in
                            Text(device.lastSeen.formatted(date: .omitted, time: .shortened))
                        }.width(min: 90, ideal: 110)
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Your router (\(result.network.gateway ?? "not identified")) is not counted. Times are since this app opened.")
                        .font(.caption).foregroundStyle(.secondary)
                    if result.network.isPartial {
                        notice("Scanned \(result.network.hosts.count.formatted()) of \(result.network.totalHosts.formatted()) addresses. The real number is likely higher.", symbol: "chart.pie", color: .secondary)
                    }
                    if result.isHiddenNetwork {
                        notice("Only this Mac is visible. This network may hide devices from each other, which is common on public Wi-Fi. If this is your own network, check Local Network permission in System Settings.", symbol: "eye.slash", color: .secondary)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: model.scanning ? "dot.radiowaves.left.and.right" : "network")
                            .font(.system(size: 32)).foregroundStyle(accent.opacity(0.8))
                        Text(model.scanning ? "Looking for responding devices…" : "Connect to your Wi-Fi")
                            .font(.headline)
                        Text(model.scanning ? "A scan usually takes 10–40 seconds. Keep this Mac connected." : "The list fills in automatically. No router password needed.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            notice("Some phones hide their name and show as Unknown device. Sleeping phones may be missed, so the real number can be a little higher.", symbol: "info.circle", color: .secondary)
        }
        .padding(26)
        }
        .frame(minWidth: 880, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
    }

    private func metric(_ value: String, _ title: String, _ detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 38, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
            .font(.callout).foregroundStyle(color)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct WiFiMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = Monitor()
    var body: some Scene {
        Window("Who's on My Wi-Fi", id: "main") {
            Dashboard(model: model)
                .onAppear { if !model.monitoring { model.setMonitoring(true) } }
        }
        .defaultSize(width: 960, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Show local history folder", action: model.showHistory)
            }
        }
    }
}
