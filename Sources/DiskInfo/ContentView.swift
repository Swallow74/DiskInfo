import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            detail
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                .help("Refresh disks")
            }
        }
    }

    private func refresh() {
        Task { @MainActor in
            await state.refresh()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if state.isLoading && state.disks.isEmpty {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning disks...")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.error, state.disks.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Error")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: Bindable(state).selectedDisk) {
                ForEach(state.disks) { disk in
                    DiskRow(disk: disk)
                        .tag(disk)
                }
                if state.isLoadingSmart {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Loading SMART data...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if state.isLoading && state.disks.isEmpty {
            ContentUnavailableView(
                "Scanning Disks",
                systemImage: "magnifyingglass.circle",
                description: Text("Looking for connected drives...")
            )
        } else if state.disks.isEmpty {
            ContentUnavailableView(
                "No Disks Found",
                systemImage: "externaldrive.slash",
                description: Text("Connect a drive and click refresh")
            )
        } else if let disk = state.selectedDisk {
            DiskDetailView(disk: disk, isLoadingSmart: state.isLoadingSmart)
        } else {
            ContentUnavailableView(
                "Select a Disk",
                systemImage: "externaldrive",
                description: Text("Choose a disk from the sidebar")
            )
        }
    }
}

struct DiskRow: View {
    let disk: Disk

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: disk.isSolidState
                  ? "externaldrive.fill"
                  : "externaldrive")
                .font(.title)
                .foregroundStyle(disk.isInternal ? .blue : .teal)
                .symbolVariant(.fill)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(disk.model)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(disk.size)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                    if disk.isInternal {
                        Text("Internal")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue))
                    } else {
                        Text("External")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.teal))
                    }
                }
            }

            Spacer()

            Circle()
                .fill(disk.smartStatus.isGood ? Color.green : (disk.smartStatus == .failing ? .red : .orange))
                .frame(width: 10, height: 10)
        }
        .padding(.vertical, 6)
    }
}
