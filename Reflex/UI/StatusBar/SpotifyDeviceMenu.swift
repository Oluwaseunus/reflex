import SwiftUI

struct SpotifyDeviceMenu: View {
    @ObservedObject private var controller = SpotifyBackgroundController.shared
    @State private var isShowingDevices = false

    private var deviceLabel: String {
        if let currentDeviceName = controller.currentDeviceName {
            return "Playing on: \(currentDeviceName)"
        }
        if controller.isUpdatingDevices { return "Checking devices…" }
        return controller.deviceError == nil ? "Playback devices" : "Devices unavailable"
    }

    var body: some View {
        Button {
            isShowingDevices.toggle()
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
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .popover(isPresented: $isShowingDevices, arrowEdge: .bottom) {
            deviceList
        }
        .onChange(of: isShowingDevices) { _, isShowing in
            if isShowing {
                controller.refreshDevices()
            }
        }
    }

    // A live list lets the first refresh finish while the dropdown stays open.
    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.isUpdatingDevices {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking devices…")
                }
                .foregroundStyle(.secondary)
            } else if let error = controller.deviceError {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if controller.devices.isEmpty {
                Text("No devices available")
                    .foregroundStyle(.secondary)
            }

            if !controller.devices.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(controller.devices) { device in
                            Button {
                                guard !device.isCurrent else { return }
                                isShowingDevices = false
                                controller.switchDevice(device)
                            } label: {
                                HStack {
                                    Text(device.name)
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    if device.isCurrent {
                                        Image(systemName: "checkmark")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .disabled(device.isCurrent || controller.isUpdatingDevices)
                        }
                    }
                }
                .frame(height: min(CGFloat(controller.devices.count) * 40, 240))
            }

            Divider()
            Button("Refresh devices") {
                controller.refreshDevices()
            }
            .disabled(controller.isUpdatingDevices)
        }
        .font(.system(size: 12))
        .padding(12)
        .frame(width: 260)
    }
}
