import SwiftUI

struct DiskDetailView: View {
    let disk: Disk
    var isLoadingSmart: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerCard
                if isLoadingSmart {
                    smartLoadingBanner
                } else if let smart = disk.smartData {
                    healthGrid(smart: smart)
                    usageSection(smart: smart)
                    reliabilitySection(smart: smart)
                if disk.isNVMe {
                    nvmeSection(smart: smart)
                } else {
                    sataSection(smart: smart)
                }
                technicalSection(smart: smart)
            } else if disk.smartStatus == .unsupported || disk.smartStatus == .unknown {
                    unsupportedBanner
                }
                identitySection
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(disk.isInternal
                          ? LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [.teal, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: disk.isSolidState ? "externaldrive.fill" : "externaldrive")
                    .font(.title)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(disk.model)
                    .font(.title)
                    .fontWeight(.bold)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label(disk.interface, systemImage: "cable.connector")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(disk.size)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(disk.isInternal ? "Internal" : "External")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusBadge
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(disk.smartStatus.isGood ? Color.green : (disk.smartStatus == .failing ? .red : .orange))
                .frame(width: 12, height: 12)
            Text(disk.smartStatus == .verified ? "Healthy"
                 : disk.smartStatus == .failing ? "Failing"
                 : disk.smartStatus == .unsupported ? "N/A"
                 : "Unknown")
                .font(.body)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(disk.smartStatus.isGood ? Color.green.opacity(0.15)
                      : disk.smartStatus == .failing ? Color.red.opacity(0.15)
                      : Color.orange.opacity(0.15))
        )
    }

    // MARK: - Health Grid

    private func healthGrid(smart: Disk.SmartData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "heart.text.square", title: "Health", color: .green)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                StatCard(
                    icon: "thermometer.medium",
                    iconColor: smart.temperature > 60 ? .red : (smart.temperature > 50 ? .orange : .green),
                    label: "Temperature",
                    value: "\(smart.temperature)°C",
                    extraRows: smart.temperatureSensors.isEmpty ? nil
                        : smart.temperatureSensors.enumerated().map { (idx, temp) in
                            ExtraRow(icon: "sensor.fill", text: "Sensor \(idx + 2):  \(temp)°C", color: temp > 60 ? .red : (temp > 50 ? .orange : .green))
                        }
                )
                StatCard(
                    icon: "battery.100",
                    iconColor: barColor(percent: smart.healthPercent),
                    label: "Health",
                    value: "\(smart.healthPercent)%",
                    bar: BarConfig(value: smart.healthPercent, color: barColor(percent: smart.healthPercent))
                )
                StatCard(
                    icon: "square.grid.3x3.fill",
                    iconColor: smart.availableSpare > 20 ? .purple : .orange,
                    label: "Spare",
                    value: "\(smart.availableSpare)%",
                    subtitle: "Threshold: \(smart.availableSpareThreshold)%",
                    bar: BarConfig(value: smart.availableSpare, color: .purple)
                )
                StatCard(
                    icon: "clock",
                    iconColor: .orange,
                    label: "Power On",
                    value: formatHours(smart.powerOnHours),
                    subtitle: "\(smart.powerCycles) cycles"
                )
            }
        }
    }

    // MARK: - Usage

    private func usageSection(smart: Disk.SmartData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "chart.bar.xaxis", title: "Usage", color: .blue)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                StatCard(
                    icon: "arrow.down.to.line",
                    iconColor: .blue,
                    label: "Data Read",
                    value: smart.dataRead,
                    subtitle: "\(smart.hostReadCommands.formatted()) commands"
                )
                StatCard(
                    icon: "arrow.up.to.line",
                    iconColor: .orange,
                    label: "Data Written",
                    value: smart.dataWritten,
                    subtitle: "\(smart.hostWriteCommands.formatted()) commands"
                )

            }
        }
    }

    // MARK: - Reliability

    private func reliabilitySection(smart: Disk.SmartData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "checkmark.shield", title: "Reliability", color: .indigo)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                StatCard(
                    icon: "exclamationmark.circle",
                    iconColor: smart.mediaErrors == 0 ? .green : .red,
                    label: "Media Errors",
                    value: "\(smart.mediaErrors)",
                    subtitle: "Data integrity"
                )
                StatCard(
                    icon: "poweroff",
                    iconColor: smart.unsafeShutdowns == 0 ? .green : .orange,
                    label: "Unsafe Shutdowns",
                    value: "\(smart.unsafeShutdowns)",
                    subtitle: "Unexpected power loss"
                )
                StatCard(
                    icon: "exclamationmark.triangle",
                    iconColor: smart.criticalWarning == "0x00" ? .green : .red,
                    label: "Critical Warning",
                    value: smart.criticalWarning,
                    subtitle: smart.criticalWarning == "0x00" ? "None" : "Warning active"
                )
                if smart.errorLogEntries > 0 {
                    StatCard(
                        icon: "list.bullet.rectangle",
                        iconColor: smart.errorLogEntries == 0 ? .green : .orange,
                        label: "Error Log",
                        value: "\(smart.errorLogEntries)",
                        subtitle: "Logged entries"
                    )
                }
                if smart.warningTempTimeMins > 0 || smart.criticalTempTimeMins > 0 {
                    StatCard(
                        icon: "thermometer.sun",
                        iconColor: smart.criticalTempTimeMins > 0 ? .red : .orange,
                        label: "Thermal Events",
                        value: "W: \(smart.warningTempTimeMins)m  C: \(smart.criticalTempTimeMins)m",
                        subtitle: "Warning / Critical temp time"
                    )
                }
            }
        }
    }

    // MARK: - NVMe

    private func nvmeSection(smart: Disk.SmartData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "cpu", title: "NVMe", color: .cyan)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                StatCard(
                    icon: "hare",
                    iconColor: .teal,
                    label: "Controller Busy",
                    value: formatMinutes(smart.controllerBusyMinutes)
                )
                if !smart.nvmeVersion.isEmpty {
                    StatCard(
                        icon: "doc.text",
                        iconColor: .gray,
                        label: "NVMe Version",
                        value: smart.nvmeVersion
                    )
                }
                StatCard(
                    icon: "list.bullet.rectangle",
                    iconColor: smart.errorLogEntries == 0 ? .green : .orange,
                    label: "Error Log Entries",
                    value: "\(smart.errorLogEntries)"
                )
            }
        }
    }

    // MARK: - SATA

    private func sataSection(smart: Disk.SmartData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "gearshape.2", title: "SATA Attributes", color: .brown)
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 14) {
                if let v = smart.reallocatedSectors {
                    StatCard(icon: "exclamationmark.arrow.trianglehead.counterclockwise",
                             iconColor: v == 0 ? .green : .red,
                             label: "Reallocated Sectors", value: "\(v)")
                }
                if let v = smart.pendingSector {
                    StatCard(icon: "clock.arrow.circlepath",
                             iconColor: v == 0 ? .green : .orange,
                             label: "Pending Sector", value: "\(v)")
                }
                if let v = smart.offlineUncorrectable {
                    StatCard(icon: "xmark.circle",
                             iconColor: v == 0 ? .green : .red,
                             label: "Offline Uncorrectable", value: "\(v)")
                }
                if let v = smart.rawReadErrorRate {
                    StatCard(icon: "antenna.radiowaves.left.and.right",
                             iconColor: .gray,
                             label: "Raw Read Errors", value: "\(v)")
                }
                if let v = smart.startStopCount {
                    StatCard(icon: "poweron",
                             iconColor: .orange,
                             label: "Start/Stop Count", value: "\(v)")
                }
                if let v = smart.spinUpTime {
                    StatCard(icon: "timer",
                             iconColor: .blue,
                             label: "Spin-Up Time", value: "\(v)")
                }
                if let v = smart.udmaCrcErrors {
                    StatCard(icon: "wifi.slash",
                             iconColor: v == 0 ? .green : .red,
                             label: "UDMA CRC Errors", value: "\(v)")
                }
            }
        }
    }

    // MARK: - Technical Details

    private func technicalSection(smart: Disk.SmartData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "gearshape.2", title: "Technical Details", color: .secondary)

            VStack(spacing: 0) {
                if smart.warningThreshold > 0 {
                    techRow(label: "Warning Temp", value: "\(smart.warningThreshold)°C")
                    Divider().padding(.leading, 180)
                }
                if smart.criticalThreshold > 0 {
                    techRow(label: "Critical Temp", value: "\(smart.criticalThreshold)°C")
                    Divider().padding(.leading, 180)
                }
                if !smart.powerStates.isEmpty {
                    techRow(label: "Power States", value: "\(smart.powerStates.count) states")
                    Divider().padding(.leading, 180)
                    ForEach(smart.powerStates, id: \.state) { ps in
                        techRow(label: "  PS\(ps.state)",
                                value: "\(ps.maxPower) max  \(ps.activePower) active  \(ps.idlePower) idle  \(ps.entryLatency)/\(ps.exitLatency)µs lat")
                        Divider().padding(.leading, 180)
                    }
                }
                if !smart.pciVendorId.isEmpty {
                    techRow(label: "PCI Vendor", value: smart.pciVendorId)
                    Divider().padding(.leading, 180)
                }
                if !smart.ieeeOui.isEmpty {
                    techRow(label: "IEEE OUI", value: smart.ieeeOui)
                    Divider().padding(.leading, 180)
                }
                if smart.controllerId > 0 {
                    techRow(label: "Controller ID", value: "\(smart.controllerId)")
                    Divider().padding(.leading, 180)
                }
                if smart.numNamespaces > 0 {
                    techRow(label: "Namespaces", value: "\(smart.numNamespaces)")
                    Divider().padding(.leading, 180)
                }
                if !smart.maxDataTransferSize.isEmpty {
                    techRow(label: "Max Transfer", value: smart.maxDataTransferSize)
                    Divider().padding(.leading, 180)
                }
                if !smart.firmwareUpdateSlots.isEmpty {
                    techRow(label: "FW Updates", value: smart.firmwareUpdateSlots)
                    Divider().padding(.leading, 180)
                }
                if !smart.optionalAdminCommands.isEmpty {
                    techRow(label: "Admin Cmds", value: smart.optionalAdminCommands)
                    Divider().padding(.leading, 180)
                }
                if !smart.optionalNvmCommands.isEmpty {
                    techRow(label: "NVM Cmds", value: smart.optionalNvmCommands)
                    Divider().padding(.leading, 180)
                }
                if !smart.logPageAttributes.isEmpty {
                    techRow(label: "Log Attrs", value: smart.logPageAttributes)
                    Divider().padding(.leading, 180)
                }
                ForEach(smart.rawDetails, id: \.self) { detail in
                    techRow(label: detail.label, value: detail.value)
                    Divider().padding(.leading, 180)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func techRow(label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .trailing)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "info.circle", title: "Identity", color: .gray)
            VStack(spacing: 0) {
                identityRow(label: "Model", value: disk.model)
                Divider().padding(.leading, 140)
                identityRow(label: "Serial", value: disk.serial)
                Divider().padding(.leading, 140)
                identityRow(label: "Firmware", value: disk.firmware)
                Divider().padding(.leading, 140)
                identityRow(label: "Interface", value: disk.interface)
                Divider().padding(.leading, 140)
                identityRow(label: "BSD Name", value: "/dev/\(disk.bsdName)")
                Divider().padding(.leading, 140)
                identityRow(label: "Type", value: disk.isSolidState ? "Solid State" : "HDD")
                Divider().padding(.leading, 140)
                identityRow(label: "Location", value: disk.isInternal ? "Internal" : "External")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func identityRow(label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Banners

    private var smartLoadingBanner: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 4) {
                Text("Loading SMART Data")
                    .font(.body)
                    .fontWeight(.medium)
                Text("Authorize the admin prompt to read health data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var unsupportedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "questionmark.circle")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("SMART Data Unavailable")
                    .font(.body)
                    .fontWeight(.medium)
                Text("This disk does not support SMART or smartmontools is not installed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
        }
    }

    private func formatHours(_ hours: Int) -> String {
        if hours < 60 { return "\(hours)m" }
        let h = hours / 60
        let m = hours % 60
        if h < 24 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        let days = h / 24
        let rem = h % 24
        return "\(days)d \(rem)h"
    }

    private func formatMinutes(_ mins: Int) -> String {
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        let m = mins % 60
        if h < 24 { return m > 0 ? "\(h)h \(m)min" : "\(h)h" }
        let days = h / 24
        let rem = h % 24
        return "\(days)d \(rem)h"
    }

    private func barColor(percent: Int) -> Color {
        if percent > 80 { return .green }
        if percent > 50 { return .blue }
        if percent > 20 { return .orange }
        return .red
    }
}

// MARK: - ExtraRow

struct ExtraRow: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
}

// MARK: - StatCard

struct BarConfig {
    let value: Int
    let color: Color
}

struct StatCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var subtitle: String? = nil
    var bar: BarConfig? = nil
    var extraRows: [ExtraRow]? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(label)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    if let bar = bar {
                        ProgressView(value: Double(bar.value) / 100.0)
                            .tint(bar.color)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)

            if let rows = extraRows, !rows.isEmpty {
                Divider()
                    .padding(.horizontal, 16)
                ForEach(rows) { row in
                    HStack(spacing: 16) {
                        Image(systemName: row.icon)
                            .font(.body)
                            .foregroundStyle(row.color)
                            .frame(width: 28)
                        Text(row.text)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
