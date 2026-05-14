import Foundation

actor DiskService {
    enum DiskServiceError: Error, LocalizedError {
        case commandFailed(String)
        case parseFailed(String)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .commandFailed(let cmd): return "Command failed: \(cmd)"
            case .parseFailed(let detail): return "Parse error: \(detail)"
            case .authenticationFailed: return "Authentication required to read SMART data"
            }
        }
    }

    private var smartCtlPath: String {
        let paths = ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl"]
        for p in paths where FileManager.default.fileExists(atPath: p) {
            return p
        }
        return "/opt/homebrew/bin/smartctl"
    }

    // MARK: - Public API

    func scanDisks() async throws -> [Disk] {
        let output = try await runDiskutil(args: ["list"])
        let identifiers = parseDiskIdentifiers(from: output)

        var disks: [Disk] = []
        for id in identifiers {
            if let basic = try? await fetchBasicInfo(bsdName: id) {
                disks.append(basic.toDisk(bsdName: id))
            }
        }
        disks.sort { $0.isInternal && !$1.isInternal }
        return disks
    }

    func fetchSmartData(for disks: [Disk]) async -> [String: Disk.SmartData] {
        let names = disks.map(\.bsdName)
        guard !names.isEmpty else { return [:] }
        guard FileManager.default.fileExists(atPath: smartCtlPath) else { return [:] }

        let tmpDir = NSTemporaryDirectory()
        var scriptLines: [String] = []
        for name in names {
            let outPath = "\(tmpDir)smartctl_\(name).txt"
            scriptLines.append("\(smartCtlPath) -a /dev/\(name) > '\(outPath)' 2>&1")
        }
        let shellCmd = scriptLines.joined(separator: "; ")
        let script = "do shell script \"\(shellCmd)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        var dataMap: [String: Disk.SmartData] = [:]
        for name in names {
            let outPath = "\(tmpDir)smartctl_\(name).txt"
            guard let content = try? String(contentsOfFile: outPath, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                try? FileManager.default.removeItem(atPath: outPath)
                continue
            }
            if let smart = parseSmartOutput(content) {
                dataMap[name] = smart
            }
            try? FileManager.default.removeItem(atPath: outPath)
        }
        return dataMap
    }

    // MARK: - diskutil

    private func runDiskutil(args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = args

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
            throw DiskServiceError.commandFailed("diskutil \(args.joined(separator: " "))")
        }
        return output
    }

    private func parseDiskIdentifiers(from output: String) -> [String] {
        var identifiers: [String] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("(internal, physical):") || trimmed.contains("(external, physical):") {
                let parts = trimmed.split(separator: " ")
                if let first = parts.first {
                    let name = first.replacingOccurrences(of: ":", with: "")
                        .replacingOccurrences(of: "/dev/", with: "")
                    identifiers.append(name)
                }
            }
        }
        return identifiers
    }

    private func fetchBasicInfo(bsdName: String) async throws -> DiskBasicInfo {
        let output = try await runDiskutil(args: ["info", bsdName])
        return try parseDiskutilInfo(from: output, bsdName: bsdName)
    }

    private struct DiskBasicInfo {
        let model: String
        let serial: String
        let firmware: String
        let interface: String
        let size: String
        let sizeBytes: UInt64
        let isInternal: Bool
        let isSolidState: Bool
        let smartStatus: Disk.SMARTStatus

        func toDisk(bsdName: String) -> Disk {
            Disk(
                id: bsdName,
                bsdName: bsdName,
                model: model,
                serial: serial,
                firmware: firmware,
                interface: interface,
                size: size,
                sizeBytes: sizeBytes,
                isInternal: isInternal,
                isSolidState: isSolidState,
                smartStatus: smartStatus,
                smartData: nil
            )
        }
    }

    private func parseDiskutilInfo(from output: String, bsdName: String) throws -> DiskBasicInfo {
        let lines = output.components(separatedBy: .newlines)

        func value(for key: String) -> String? {
            for line in lines {
                if line.contains(key + ":") {
                    var val = line.components(separatedBy: ":")
                        .dropFirst().joined(separator: ":")
                        .trimmingCharacters(in: .whitespaces)
                    if let paren = val.firstIndex(of: "(") {
                        val = String(val[val.startIndex..<paren]).trimmingCharacters(in: .whitespaces)
                    }
                    return val.isEmpty ? nil : val
                }
            }
            return nil
        }

        let model = value(for: "Device / Media Name") ?? bsdName
        let serial = value(for: "Serial Number") ?? ""
        let firmware = value(for: "Firmware Version") ?? ""
        let interface = value(for: "Protocol") ?? "Unknown"

        let sizeBytes = parseDiskSize(from: output)
        let size = ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)

        let location = value(for: "Device Location") ?? value(for: "Internal") ?? ""
        let isInternal = location.contains("Internal") || location.contains("Yes")
        let isSolidState = (value(for: "Solid State") ?? "").contains("Yes")

        let smartRaw = value(for: "SMART Status")?.uppercased() ?? "UNKNOWN"
        let smartStatus: Disk.SMARTStatus
        switch smartRaw {
        case "VERIFIED": smartStatus = .verified
        case "FAILING": smartStatus = .failing
        case "NOT SUPPORTED", "UNSUPPORTED": smartStatus = .unsupported
        default: smartStatus = .unknown
        }

        return DiskBasicInfo(
            model: model,
            serial: serial,
            firmware: firmware,
            interface: interface,
            size: size,
            sizeBytes: sizeBytes,
            isInternal: isInternal,
            isSolidState: isSolidState,
            smartStatus: smartStatus
        )
    }

    private func parseDiskSize(from output: String) -> UInt64 {
        for line in output.components(separatedBy: .newlines) {
            guard line.contains("Disk Size:") || line.contains("Total Size:") else { continue }
            guard let start = line.firstIndex(of: "(") else { continue }
            guard let end = line.firstIndex(of: ")") else { continue }
            let paren = line[start...end]
            let nums = paren.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
            if let first = nums.first, let bytes = UInt64(first) {
                return bytes
            }
        }
        return 0
    }

    // MARK: - smartctl parser

    private func parseSmartOutput(_ output: String) -> Disk.SmartData? {
        if output.contains("SMART/Health Information") || output.contains("NVMe") {
            return parseNVMeSmart(output)
        }
        if output.contains("Vendor Specific SMART Attributes with Thresholds") {
            return parseATASmart(output)
        }
        return nil
    }

    // MARK: NVMe

    private func parseNVMeSmart(_ output: String) -> Disk.SmartData? {
        guard output.contains("SMART overall-health") || output.contains("SMART/Health Information") else {
            return nil
        }

        let lines = output.components(separatedBy: .newlines)

        func extract(_ key: String) -> String? {
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix(key) {
                    let val = line.components(separatedBy: ":")
                        .dropFirst().joined(separator: ":")
                        .trimmingCharacters(in: .whitespaces)
                    return val.isEmpty ? nil : val
                }
            }
            return nil
        }

        func parseInt(_ key: String) -> Int? {
            guard let raw = extract(key) else { return nil }
            let cleaned = raw.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).first ?? raw
            return Int(cleaned)
        }

        func parsePercent(_ key: String) -> Int? {
            guard let raw = extract(key) else { return nil }
            return Int(raw.replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespaces))
        }

        func parseDataUnits(_ key: String) -> (raw: UInt64, human: String)? {
            guard let raw = extract(key) else { return nil }
            let parts = raw.components(separatedBy: "[")
            let rawStr = parts[0].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: "")
            guard let rawValue = UInt64(rawStr) else { return nil }
            let human = parts.count > 1
                ? parts[1].replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                : "\(rawValue)"
            return (rawValue, human)
        }

        func parseUInt64(_ key: String) -> UInt64? {
            guard let raw = extract(key) else { return nil }
            return UInt64(raw.replacingOccurrences(of: ",", with: ""))
        }

        func rawLine(_ key: String) -> String? {
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix(key) {
                    return line.trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }

        func hexStr(_ key: String) -> String {
            guard let line = rawLine(key) else { return "" }
            return line.components(separatedBy: ":").dropFirst().joined()
                .trimmingCharacters(in: .whitespaces)
        }

        let temp = parseInt("Temperature") ?? 0
        let tempSensors: [Int] = {
            var sensors: [Int] = []
            for i in 2...8 {
                if let t = parseInt("Temperature Sensor \(i)") {
                    sensors.append(t)
                }
            }
            return sensors
        }()

        let nvmeVersion: String = {
            for line in lines {
                if line.contains("NVMe Version:") {
                    return line.components(separatedBy: ":")
                        .dropFirst().joined(separator: ":")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            return ""
        }()

        let spare = parsePercent("Available Spare") ?? 100
        let spareThreshold = parsePercent("Available Spare Threshold") ?? 10
        let used = parsePercent("Percentage Used") ?? 0

        let dataRead = parseDataUnits("Data Units Read") ?? (0, "0 GB")
        let dataWritten = parseDataUnits("Data Units Written") ?? (0, "0 GB")

        let hours = parseInt("Power On Hours") ?? 0
        let cycles = parseInt("Power Cycles") ?? 0
        let shutdowns = parseInt("Unsafe Shutdowns") ?? 0
        let errors = parseInt("Media and Data Integrity Errors") ?? 0
        let critical = extract("Critical Warning") ?? "0x00"
        let readCmds = parseUInt64("Host Read Commands") ?? 0
        let writeCmds = parseUInt64("Host Write Commands") ?? 0
        let busyMinutes = parseInt("Controller Busy Time") ?? 0
        let errLogEntries = parseInt("Error Information Log Entries") ?? 0
        let warnTempTime = parseInt("Warning  Comp. Temperature Time") ?? 0
        let critTempTime = parseInt("Critical Comp. Temperature Time") ?? 0
        let warnThreshold = parseInt("Warning  Comp. Temp. Threshold") ?? 0
        let critThreshold = parseInt("Critical Comp. Temp. Threshold") ?? 0

        // Info section
        let pciVendor = hexStr("PCI Vendor/Subsystem ID")
        let ieeeOui = hexStr("IEEE OUI Identifier")
        let ctrlId = parseInt("Controller ID") ?? 0
        let namespaces = parseInt("Number of Namespaces") ?? 1
        let maxXfer: String = {
            guard let raw = extract("Maximum Data Transfer Size") else { return "" }
            return raw
        }()
        let fwSlots = extract("Firmware Updates") ?? ""
        let adminCmds = extract("Optional Admin Commands") ?? ""
        let nvmCmds = extract("Optional NVM Commands") ?? ""
        let logAttrs = extract("Log Page Attributes") ?? ""

        // Power states
        var powerStates: [Disk.PowerState] = []
        var inPowerSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Supported Power States" {
                inPowerSection = true
                continue
            }
            if inPowerSection {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 8, let stateNum = Int(parts[0]) {
                    let maxPw = String(parts[1])
                    let actPw = String(parts[2])
                    let idlePw = String(parts[3])
                    let entLat = Int(parts[6]) ?? 0
                    let extLat = Int(parts[7]) ?? 0
                    powerStates.append(Disk.PowerState(
                        state: stateNum,
                        maxPower: maxPw,
                        activePower: actPw,
                        idlePower: idlePw,
                        entryLatency: entLat,
                        exitLatency: extLat
                    ))
                } else if parts.count >= 1 && !parts[0].allSatisfy({ $0.isNumber }) {
                    inPowerSection = false
                }
            }
        }

        // Raw details for everything else
        var rawDetails: [Disk.RawDetail] = []
        let skipKeys: Set = ["Model Number", "Serial Number", "Firmware Version",
            "PCI Vendor/Subsystem ID", "IEEE OUI Identifier", "Controller ID",
            "Number of Namespaces", "Maximum Data Transfer Size", "Firmware Updates",
            "Optional Admin Commands", "Optional NVM Commands", "Log Page Attributes",
            "NVMe Version", "Local Time", "SMART overall-health"]
        let smartKeys: Set = ["Critical Warning", "Temperature", "Available Spare",
            "Available Spare Threshold", "Percentage Used", "Data Units Read",
            "Data Units Written", "Host Read Commands", "Host Write Commands",
            "Controller Busy Time", "Power Cycles", "Power On Hours",
            "Unsafe Shutdowns", "Media and Data Integrity Errors",
            "Error Information Log Entries", "Warning  Comp. Temperature Time",
            "Critical Comp. Temperature Time", "Warning  Comp. Temp. Threshold",
            "Critical Comp. Temp. Threshold", "Temperature Sensor"]
        let allSkip = skipKeys.union(smartKeys)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(":") else { continue }
            let key = trimmed.components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !key.isEmpty, !allSkip.contains(key),
                  !key.hasPrefix("Temperature Sensor") else { continue }
            let val = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)
            guard !val.isEmpty else { continue }
            rawDetails.append(Disk.RawDetail(label: key, value: val))
        }

        return Disk.SmartData(
            temperature: temp,
            temperatureSensors: tempSensors,
            warningTempTimeMins: warnTempTime,
            criticalTempTimeMins: critTempTime,
            warningThreshold: warnThreshold,
            criticalThreshold: critThreshold,
            availableSpare: spare,
            availableSpareThreshold: spareThreshold,
            percentageUsed: used,
            nvmeVersion: nvmeVersion,
            dataRead: dataRead.human,
            dataWritten: dataWritten.human,
            dataReadRaw: dataRead.raw * 512 * 1000,
            dataWrittenRaw: dataWritten.raw * 512 * 1000,
            hostReadCommands: readCmds,
            hostWriteCommands: writeCmds,
            powerOnHours: hours,
            powerCycles: cycles,
            unsafeShutdowns: shutdowns,
            controllerBusyMinutes: busyMinutes,
            mediaErrors: errors,
            errorLogEntries: errLogEntries,
            criticalWarning: critical,
            reallocatedSectors: nil,
            pendingSector: nil,
            offlineUncorrectable: nil,
            spinUpTime: nil,
            startStopCount: nil,
            rawReadErrorRate: nil,
            udmaCrcErrors: nil,
            pciVendorId: pciVendor,
            ieeeOui: ieeeOui,
            controllerId: ctrlId,
            numNamespaces: namespaces,
            maxDataTransferSize: maxXfer,
            firmwareUpdateSlots: fwSlots,
            optionalAdminCommands: adminCmds,
            optionalNvmCommands: nvmCmds,
            logPageAttributes: logAttrs,
            powerStates: powerStates,
            rawDetails: rawDetails
        )
    }

    // MARK: ATA / SATA

    private func parseATASmart(_ output: String) -> Disk.SmartData? {
        let lines = output.components(separatedBy: .newlines)

        func extract(_ key: String) -> String? {
            for line in lines {
                if line.contains(key + ":") {
                    let val = line.components(separatedBy: ":")
                        .dropFirst().joined(separator: ":")
                        .trimmingCharacters(in: .whitespaces)
                    return val.isEmpty ? nil : val
                }
            }
            return nil
        }

        func parseInt(_ key: String) -> Int? {
            guard let raw = extract(key) else { return nil }
            return Int(raw.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).first ?? "")
        }

        let temp = parseInt("194 Temperature_Celsius") ?? parseInt("Temperature_Celsius") ?? 0

        let spare: Int = {
            for line in lines {
                if line.contains("5 Reallocated_Sector_Ct") || line.contains("Reallocated_Sector_Ct") {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 10 {
                        if let norm = Int(parts[4]) { return norm }
                    }
                }
            }
            return 100
        }()

        func ataAttr(_ name: String) -> Int? {
            for line in lines {
                if line.contains(name) {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 10, let raw = Int(parts[9]) {
                        return raw
                    }
                }
            }
            return nil
        }

        func ataAttrNorm(_ name: String) -> Int? {
            for line in lines {
                if line.contains(name) {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 5, let norm = Int(parts[4]) {
                        return norm
                    }
                }
            }
            return nil
        }

        let reallocated = ataAttr("Reallocated_Sector_Ct")
        let pending = ataAttr("Current_Pending_Sector")
        let uncorrectable = ataAttr("Offline_Uncorrectable")
        let spinUp = ataAttr("Spin_Up_Time")
        let startStop = ataAttr("Start_Stop_Count")
        let rawReadErr = ataAttr("Raw_Read_Error_Rate")
        let udmaCRC = ataAttr("UDMA_CRC_Error_Count")
        let hours = ataAttr("Power_On_Hours") ?? 0
        let cycles = ataAttr("Power_Cycle_Count") ?? 0
        let used = 100 - (ataAttrNorm("Reallocated_Sector_Ct") ?? 100)
        let errors = ataAttr("Reported_Uncorrect") ?? 0

        return Disk.SmartData(
            temperature: temp,
            temperatureSensors: [],
            warningTempTimeMins: 0,
            criticalTempTimeMins: 0,
            warningThreshold: 0,
            criticalThreshold: 0,
            availableSpare: max(0, spare),
            availableSpareThreshold: 10,
            percentageUsed: max(0, min(100, used)),
            nvmeVersion: "",
            dataRead: "",
            dataWritten: "",
            dataReadRaw: 0,
            dataWrittenRaw: 0,
            hostReadCommands: 0,
            hostWriteCommands: 0,
            powerOnHours: hours,
            powerCycles: cycles,
            unsafeShutdowns: 0,
            controllerBusyMinutes: 0,
            mediaErrors: errors,
            errorLogEntries: 0,
            criticalWarning: "0x00",
            reallocatedSectors: reallocated,
            pendingSector: pending,
            offlineUncorrectable: uncorrectable,
            spinUpTime: spinUp,
            startStopCount: startStop,
            rawReadErrorRate: rawReadErr,
            udmaCrcErrors: udmaCRC,
            pciVendorId: "",
            ieeeOui: "",
            controllerId: 0,
            numNamespaces: 0,
            maxDataTransferSize: "",
            firmwareUpdateSlots: "",
            optionalAdminCommands: "",
            optionalNvmCommands: "",
            logPageAttributes: "",
            powerStates: [],
            rawDetails: []
        )
    }
}
