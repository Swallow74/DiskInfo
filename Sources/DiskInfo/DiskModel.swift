import Foundation

struct Disk: Identifiable, Hashable, Sendable {
    let id: String
    let bsdName: String
    let model: String
    let serial: String
    let firmware: String
    let interface: String
    let size: String
    let sizeBytes: UInt64
    let isInternal: Bool
    let isSolidState: Bool
    let smartStatus: SMARTStatus
    var smartData: SmartData?

    enum SMARTStatus: String, Hashable, Sendable {
        case verified = "VERIFIED"
        case failing = "FAILING"
        case unsupported = "UNSUPPORTED"
        case unknown = "UNKNOWN"

        var isGood: Bool { self == .verified }
    }

    var isNVMe: Bool { interface.contains("PCI-Express") || interface.contains("NVMe") || interface.contains("Apple Fabric") }

    struct SmartData: Hashable, Sendable {
        // Temperatures
        let temperature: Int
        let temperatureSensors: [Int]
        let warningTempTimeMins: Int
        let criticalTempTimeMins: Int
        let warningThreshold: Int
        let criticalThreshold: Int

        // Wear & spare
        let availableSpare: Int
        let availableSpareThreshold: Int
        let percentageUsed: Int
        let nvmeVersion: String

        // Data volume
        let dataRead: String
        let dataWritten: String
        let dataReadRaw: UInt64
        let dataWrittenRaw: UInt64
        let hostReadCommands: UInt64
        let hostWriteCommands: UInt64

        // Power & reliability
        let powerOnHours: Int
        let powerCycles: Int
        let unsafeShutdowns: Int
        let controllerBusyMinutes: Int
        let mediaErrors: Int
        let errorLogEntries: Int
        let criticalWarning: String

        // SATA-specific (nil for NVMe)
        let reallocatedSectors: Int?
        let pendingSector: Int?
        let offlineUncorrectable: Int?
        let spinUpTime: Int?
        let startStopCount: Int?
        let rawReadErrorRate: Int?
        let udmaCrcErrors: Int?

        // Technical details (NVMe info section)
        let pciVendorId: String
        let ieeeOui: String
        let controllerId: Int
        let numNamespaces: Int
        let maxDataTransferSize: String
        let firmwareUpdateSlots: String
        let optionalAdminCommands: String
        let optionalNvmCommands: String
        let logPageAttributes: String
        let powerStates: [PowerState]

        // Raw details for everything else
        let rawDetails: [RawDetail]

        var healthPercent: Int { max(0, 100 - percentageUsed) }
    }

    struct PowerState: Hashable, Sendable {
        let state: Int
        let maxPower: String
        let activePower: String
        let idlePower: String
        let entryLatency: Int
        let exitLatency: Int
    }

    struct RawDetail: Hashable, Sendable {
        let label: String
        let value: String
    }
}
