import AppKit
import Observation
import ServiceManagement
import SwiftUI

@main
struct AnnoyntApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(settings: .shared, status: .shared)
        } label: {
            Image(systemName: Settings.shared.enabled ? "rectangle.2.swap" : "pause.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Runtime status shown in the menu (permissions, login item). Main-thread only.
@Observable
final class AppStatus {
    static let shared = AppStatus()

    var accessibilityGranted = Permissions.isTrusted
    var interceptorRunning = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var permissionTimer: Timer?

    func start() {
        if accessibilityGranted {
            startInterceptor()
        } else {
            Permissions.request()
            waitForPermission()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Annoynt: launch-at-login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func startInterceptor() {
        let keys = KeyInterceptor.shared.start()
        let swipes = SwipeInterceptor.shared.start()
        interceptorRunning = keys && swipes
    }

    /// The tap can only be created once the user ticks Annoynt in
    /// Accessibility settings; poll until then.
    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self, Permissions.isTrusted else { return }
            timer.invalidate()
            self.accessibilityGranted = true
            self.startInterceptor()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SkyLight.isAvailable else {
            NSLog("Annoynt: SkyLight space APIs unavailable on this macOS version")
            return
        }
        AppStatus.shared.start()
    }
}
