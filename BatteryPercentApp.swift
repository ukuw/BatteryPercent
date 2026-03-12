import SwiftUI
import IOKit.ps
import ServiceManagement   // for SMAppService (launch at login)

@main
struct BatteryPercentApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()   // no visible window
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    let updateInterval: TimeInterval = 10.0

    private let statusMenu = NSMenu()

    // Launch-at-login status using SMAppService (macOS 13+)[web:95][web:101]
    private var launchAtLoginEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return false
            }
        }
        set {
            guard #available(macOS 13.0, *) else { return }
            if newValue {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "–"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupMenu()
        updateBattery()

        Timer.scheduledTimer(timeInterval: updateInterval,
                             target: self,
                             selector: #selector(updateBattery),
                             userInfo: nil,
                             repeats: true)
    }

    // MARK: - Status item click

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left click: no action for now
        }
    }

    // MARK: - Menu

    private func setupMenu() {
        statusMenu.removeAllItems()

        // Launch at Login toggle
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.state = launchAtLoginEnabled ? .on : .off
        launchItem.target = self
        statusMenu.addItem(launchItem)

        statusMenu.addItem(NSMenuItem.separator())

        // About / Website
        let aboutItem = NSMenuItem(
            title: "About / Website",
            action: #selector(openWebsite),
            keyEquivalent: ""
        )
        aboutItem.target = self
        statusMenu.addItem(aboutItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Uninstall
        let uninstallItem = NSMenuItem(
            title: "Uninstall…",
            action: #selector(uninstallApp),
            keyEquivalent: ""
        )
        uninstallItem.target = self
        statusMenu.addItem(uninstallItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        launchAtLoginEnabled = newValue
        sender.state = newValue ? .on : .off
    }

    @objc private func openWebsite() {
        if let url = URL(string: "https://ukuw.github.io") {
            NSWorkspace.shared.open(url)   // open in default browser[web:88][web:97]
        }
    }

    @objc private func uninstallApp() {
        let alert = NSAlert()
        alert.messageText = "Uninstall BatteryPercent?"
        alert.informativeText = "This will move the app to the Trash. You can restore it from the Trash if you change your mind."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Best effort: disable launch at login first
        launchAtLoginEnabled = false

        // Move the app bundle to Trash, like Finder does[web:107][web:110][web:116]
        let fileManager = FileManager.default
        let appURL = Bundle.main.bundleURL

        do {
            try fileManager.trashItem(at: appURL, resultingItemURL: nil)
        } catch {
            // If this fails, we just quit without uninstalling
        }

        NSApp.terminate(self)
    }

    @objc private func quitApp() {
        NSApp.terminate(self)
    }

    // MARK: - Battery

    @objc func updateBattery() {
        let percentage = getBatteryPercentage()
        statusItem.button?.title = "\(percentage)%"
    }

    private func getBatteryPercentage() -> Int {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
            let capacity = description[kIOPSCurrentCapacityKey as String] as? Int,
            let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
            maxCapacity > 0
        else {
            return 100
        }

        let percent = Int((Double(capacity) / Double(maxCapacity)) * 100.0)
        return Swift.max(0, Swift.min(100, percent))
    }
}
