import SwiftUI

@main
struct DiskInfoApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await appState.loadDisks()
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
    }
}

@MainActor @Observable
final class AppState {
    var disks: [Disk] = []
    var selectedDisk: Disk?
    var isLoading = false
    var isLoadingSmart = false
    var error: String?
    var lastRefresh = Date()

    private let service = DiskService()

    func loadDisks() async {
        isLoading = true
        error = nil
        do {
            let disks = try await service.scanDisks()
            self.disks = disks
            if self.selectedDisk == nil || !disks.contains(where: { $0.id == self.selectedDisk?.id }) {
                self.selectedDisk = disks.first
            }
            self.lastRefresh = Date()
            self.isLoading = false
            await loadSmartData()
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }

    private func loadSmartData() async {
        guard !disks.isEmpty else { return }
        isLoadingSmart = true
        let smartMap = await service.fetchSmartData(for: disks)
        isLoadingSmart = false
        for i in disks.indices {
            if let smart = smartMap[disks[i].bsdName] {
                disks[i].smartData = smart
            }
        }
        if smartMap.isEmpty, !disks.allSatisfy({ $0.smartStatus == .unsupported || $0.smartStatus == .unknown }) {
            if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/smartctl")
                && !FileManager.default.fileExists(atPath: "/usr/local/bin/smartctl") {
                error = "Install smartmontools: 'brew install smartmontools'"
            } else {
                error = "SMART data unavailable. Authorize the admin prompt when requested."
            }
        }
    }

    func refresh() async {
        selectedDisk = nil
        disks = []
        await loadDisks()
    }
}
