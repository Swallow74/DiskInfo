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
    var isInstalling = false

    private let service = DiskService()

    var isSmartCtlAvailable: Bool { service.isSmartCtlAvailable }
    var isHomebrewAvailable: Bool { service.isHomebrewAvailable }

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
        if isSmartCtlAvailable {
            isLoadingSmart = true
            let smartMap = await service.fetchSmartData(for: disks)
            isLoadingSmart = false
            for i in disks.indices {
                if let smart = smartMap[disks[i].bsdName] {
                    disks[i].smartData = smart
                }
            }
            if smartMap.isEmpty, !disks.allSatisfy({ $0.smartStatus == .unsupported || $0.smartStatus == .unknown }) {
                error = "SMART data unavailable. Authorize the admin prompt when requested."
            }
        }
    }

    func installAll() async {
        isInstalling = true
        error = nil

        if !isHomebrewAvailable {
            let brewOk = await service.installHomebrew()
            if !brewOk {
                error = "Homebrew installation failed. Install manually: https://brew.sh"
                isInstalling = false
                return
            }
        }

        if !isSmartCtlAvailable {
            let smartOk = await service.installSmartCtl()
            if !smartOk {
                error = "smartmontools installation failed. Try manually: brew install smartmontools"
                isInstalling = false
                return
            }
        }

        isInstalling = false
        await loadSmartData()
    }

    var installLabel: String {
        if !isHomebrewAvailable { return "Install Homebrew" }
        return "Install smartmontools"
    }

    func refresh() async {
        selectedDisk = nil
        disks = []
        await loadDisks()
    }
}
