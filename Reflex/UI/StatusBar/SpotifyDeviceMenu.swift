import AppKit
import Combine
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
            isShowingDevices = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(deviceLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .background {
            NativeSpotifyDeviceMenu(isPresented: $isShowingDevices, controller: controller)
                .allowsHitTesting(false)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Use AppKit's native tracking menu so opening this specific dropdown can
/// request fresh devices and publish them without replacing the menu's UI.
private struct NativeSpotifyDeviceMenu: NSViewRepresentable {
    @Binding var isPresented: Bool
    let controller: SpotifyBackgroundController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onClose = { isPresented = false }
        guard isPresented, !context.coordinator.isTracking else { return }
        context.coordinator.isTracking = true
        // Enter menu tracking after SwiftUI has finished its view update.
        RunLoop.main.perform(inModes: [.common]) { [weak view, coordinator = context.coordinator] in
            MainActor.assumeIsolated {
                guard let view, view.window != nil else {
                    coordinator.isTracking = false
                    coordinator.onClose?()
                    return
                }
                coordinator.open(in: view)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        let controller: SpotifyBackgroundController
        let menu = NSMenu()
        var isTracking = false
        var onClose: (() -> Void)?
        private var observation: AnyCancellable?

        init(controller: SpotifyBackgroundController) {
            self.controller = controller
            super.init()
            menu.delegate = self
            menu.autoenablesItems = false
            observation = controller.objectWillChange.sink { [weak self] _ in
                // objectWillChange arrives before the new values. Schedule the
                // rebuild after publication, including during menu tracking.
                RunLoop.main.perform(inModes: [.common]) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.isTracking else { return }
                        self.rebuildItems()
                    }
                }
            }
        }

        func open(in view: NSView) {
            rebuildItems()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY), in: view)
            isTracking = false
            onClose?()
        }

        func menuWillOpen(_ menu: NSMenu) {
            // Only this menu's opening requests devices; opening Reflex does not.
            controller.refreshDevices()
        }

        private func rebuildItems() {
            menu.removeAllItems()
            if controller.isUpdatingDevices {
                addStatus("Checking devices…")
            } else if let error = controller.deviceError {
                addStatus(error)
            } else if controller.devices.isEmpty {
                addStatus("No devices available")
            }

            for device in controller.devices {
                let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.id
                item.state = device.isCurrent ? .on : .off
                item.isEnabled = !device.isCurrent && !controller.isUpdatingDevices
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let refresh = NSMenuItem(title: "Refresh devices", action: #selector(refreshDevices), keyEquivalent: "")
            refresh.target = self
            refresh.isEnabled = !controller.isUpdatingDevices
            menu.addItem(refresh)
            menu.update()
        }

        private func addStatus(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        @objc private func selectDevice(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let device = controller.devices.first(where: { $0.id == id }),
                  !device.isCurrent else { return }
            controller.switchDevice(device)
        }

        @objc private func refreshDevices() {
            controller.refreshDevices()
        }
    }
}
