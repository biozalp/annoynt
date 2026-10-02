import AppKit
import SwiftUI

struct MenuView: View {
    @Bindable var settings: Settings
    @Bindable var status: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !status.accessibilityGranted {
                permissionBanner
            }

            speedSection
                .disabled(!settings.enabled)
                .opacity(settings.enabled ? 1 : 0.45)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Speed up trackpad swipes", isOn: $settings.handleTrackpad)
                Toggle("Handle “Switch to Desktop N” shortcuts", isOn: $settings.handleDesktopShortcuts)
                Toggle("Reverse direction", isOn: $settings.reverseDirection)
                    .help("Turn on if switches go the wrong way on your macOS build.")
                Toggle("Launch at login", isOn: Binding(
                    get: { status.launchAtLogin },
                    set: { status.setLaunchAtLogin($0) }
                ))
            }
            .toggleStyle(.checkbox)

            Divider()

            HStack {
                Text(settings.enabled ? "Driving your Space switches" : "macOS animation in use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { KeyInterceptor.shared.reloadShortcuts() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Annoynt").font(.headline)
                Text("Space switch speed").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $settings.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline.weight(.semibold))
            Text("Annoynt needs it to catch your Spaces shortcuts and drive the switch.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(SpeedPreset.all) { preset in
                    Button(preset.name) { settings.duration = preset.duration }
                        .buttonStyle(.bordered)
                        .tint(isSelected(preset) ? .accentColor : nil)
                        .controlSize(.small)
                }
            }

            HStack {
                Text("Duration")
                Spacer()
                Text(durationLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Slider(value: $settings.duration, in: 0...Settings.maxDuration, step: 0.005) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: "hare").font(.caption)
            } maximumValueLabel: {
                Image(systemName: "tortoise").font(.caption)
            }

            HStack {
                Text("Try it").font(.subheadline)
                Spacer()
                Button { SpaceSwitcher.shared.move(-1) } label: { Image(systemName: "arrow.left") }
                Button { SpaceSwitcher.shared.move(1) } label: { Image(systemName: "arrow.right") }
            }
            .disabled(!status.accessibilityGranted)
        }
    }

    private var durationLabel: String {
        settings.duration < SpeedCurve.shortest
            ? "Instant"
            : "≈ \(Int((settings.duration * 1000).rounded())) ms"
    }

    private func isSelected(_ preset: SpeedPreset) -> Bool {
        abs(settings.duration - preset.duration) < 0.005
    }
}
