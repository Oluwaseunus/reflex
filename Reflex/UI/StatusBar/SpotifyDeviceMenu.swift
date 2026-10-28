import SwiftUI

struct SpotifyDeviceMenu: View {
    @ObservedObject private var controller = SpotifyBackgroundController.shared

    private var deviceLabel: String {
        if let currentDeviceName = controller.currentDeviceName {
            return "Playing on: \(currentDeviceName)"
        }
        if controller.isUpdatingDevices { return "Checking devices…" }
        return controller.deviceError == nil ? "Playback devices" : "Devices unavailable"
    }

    var body: some View {
        Menu {
            if controller.isUpdatingDevices {
                Label("Checking devices…", systemImage: "arrow.clockwise")
            } else if let error = controller.deviceError {
                Label(error, systemImage: "exclamationmark.circle")
            }

            if controller.devices.isEmpty {
                if !controller.isUpdatingDevices && controller.deviceError == nil {
                    Text("Refresh to load devices")
                }
            } else {
                ForEach(controller.devices) { device in
                    Button {
                        guard !device.isCurrent else { return }
                        controller.switchDevice(device)
                    } label: {
                        if device.isCurrent {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                    .disabled(device.isCurrent || controller.isUpdatingDevices)
                }
            }

            if !controller.devices.isEmpty || controller.deviceError != nil {
                Divider()
            }

            Button("Refresh devices") {
                controller.refreshDevices()
            }
            .disabled(controller.isUpdatingDevices)
        } label: {
            HStack(spacing: 6) {
                Text(deviceLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
