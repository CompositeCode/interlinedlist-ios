//
//  AppDevicesView.swift
//  InterlinedList
//

import SwiftUI

/// The account's registered devices, mirroring the web's Settings → Applications.
/// Rename or forget a device; this device is marked so it is not forgotten by mistake.
struct AppDevicesView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var sync = AppSettingsSyncService()

    @State private var isLoading = true
    @State private var actionError: String?
    @State private var renaming: AppDevice?
    @State private var newName = ""

    private var thisDeviceId: String? { KeychainService.deviceId() }

    var body: some View {
        List {
            if isLoading && sync.devices.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if sync.devices.isEmpty {
                ContentUnavailableView(
                    "No devices",
                    systemImage: "laptopcomputer.and.iphone",
                    description: Text("Devices appear here once they sync their settings.")
                )
            } else {
                ForEach(sync.devices) { device in
                    row(device)
                }
            }
            if let actionError {
                Section { Text(actionError).font(.ilMono()).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await sync.loadDevices()
            isLoading = false
        }
        .refreshable { await sync.loadDevices() }
        .alert("Rename device", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let device = renaming { Task { await rename(device) } }
            }
        }
    }

    private func row(_ device: AppDevice) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(device.deviceName ?? device.deviceId)
                    .font(.ilBody(15))
                if device.deviceId == thisDeviceId {
                    Text("This device")
                        .font(.ilMono(10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ILColor.surface2)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 6) {
                if let platform = device.platform {
                    Text(platform).font(.ilMono(10)).foregroundStyle(.secondary)
                }
                if let lastSeen = device.lastSeenAt {
                    Text(relativeLastSeen(lastSeen)).font(.ilMono(10)).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if device.deviceId != thisDeviceId {
                Button(role: .destructive) {
                    Task { await forget(device) }
                } label: {
                    Label("Forget", systemImage: "trash")
                }
                .accessibilityLabel("Forget \(device.deviceName ?? device.deviceId)")
            }
            Button {
                newName = device.deviceName ?? ""
                renaming = device
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(ILColor.primary)
            .accessibilityLabel("Rename \(device.deviceName ?? device.deviceId)")
        }
    }

    private func rename(_ device: AppDevice) async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty else { return }
        do {
            try await sync.renameDevice(device.deviceId, to: name)
            actionError = nil
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            actionError = "Could not rename that device."
        }
    }

    private func forget(_ device: AppDevice) async {
        do {
            try await sync.forgetDevice(device.deviceId)
            actionError = nil
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            actionError = "Could not forget that device."
        }
    }

    private func relativeLastSeen(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return ""
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return "seen " + relative.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        AppDevicesView()
            .environmentObject(AuthState())
    }
}
