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

    // MARK: - UserDefaults Keys
    private let kChargeLimit80Key = "chargeLimit80Enabled"
    private let kBatterySaverKey  = "batterySaverEnabled"

    // MARK: - Persisted Toggles
    private var chargeLimit80Enabled: Bool {
        get { UserDefaults.standard.bool(forKey: kChargeLimit80Key) }
        set {
            UserDefaults.standard.set(newValue, forKey: kChargeLimit80Key)
            applyChargeLimit(newValue)
        }
    }

    private var batterySaverEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kBatterySaverKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: kBatterySaverKey)
            applyBatterySaver(newValue)
        }
    }

    // MARK: - Launch-at-login status using SMAppService (macOS 13+)
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

        // Re-apply persisted settings on launch
        if chargeLimit80Enabled { applyChargeLimit(true) }
        if batterySaverEnabled  { applyBatterySaver(true) }

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

        // --- Battery section header (disabled label) ---
        let batteryHeader = NSMenuItem(title: "Battery", action: nil, keyEquivalent: "")
        batteryHeader.isEnabled = false
        statusMenu.addItem(batteryHeader)

        // Limit Charging to 80%
        let chargeLimitItem = NSMenuItem(
            title: "Limit Charging to 80%",
            action: #selector(toggleChargeLimit(_:)),
            keyEquivalent: ""
        )
        chargeLimitItem.state = chargeLimit80Enabled ? .on : .off
        chargeLimitItem.target = self
        chargeLimitItem.toolTip = "Uses pmset to cap charging at 80% (Apple Silicon). Helps preserve long-term battery health."
        statusMenu.addItem(chargeLimitItem)

        // Battery Saver (Low Power Mode)
        let batterySaverItem = NSMenuItem(
            title: "Battery Saver (Low Power Mode)",
            action: #selector(toggleBatterySaver(_:)),
            keyEquivalent: ""
        )
        batterySaverItem.state = batterySaverEnabled ? .on : .off
        batterySaverItem.target = self
        batterySaverItem.toolTip = "Enables macOS Low Power Mode via pmset to extend battery life."
        statusMenu.addItem(batterySaverItem)

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

    // MARK: - Toggle Actions

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        launchAtLoginEnabled = newValue
        sender.state = newValue ? .on : .off
    }

    @objc private func toggleChargeLimit(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        chargeLimit80Enabled = newValue
        sender.state = newValue ? .on : .off
    }

    @objc private func toggleBatterySaver(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        batterySaverEnabled = newValue
        sender.state = newValue ? .on : .off
    }

    // MARK: - pmset Helpers

    /// Sets the macOS battery charge limit to 80% (Apple Silicon) or removes the limit.
    /// Requires administrator privileges; prompts via osascript if needed.
    private func applyChargeLimit(_ enable: Bool) {
        let value = enable ? "80" : "100"
        // pmset -a BATT_CHARGE_LIMIT <value> requires sudo
        runPrivilegedShell("pmset -a BATT_CHARGE_LIMIT \(value)")
    }

    /// Enables or disables macOS Low Power Mode via pmset.
    private func applyBatterySaver(_ enable: Bool) {
        let flag = enable ? "1" : "0"
        runPrivilegedShell("pmset -a lowpowermode \(flag)")
    }

    /// Runs a shell command with administrator privileges using osascript.
    private func runPrivilegedShell(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script  = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            NSLog("BatteryPercent: privileged command failed: %@", err)
        }
    }

    // MARK: - Website / Uninstall / Quit

    @objc private func openWebsite() {
        if let url = URL(string: "https://ukuw.github.io") {
            NSWorkspace.shared.open(url)
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

        launchAtLoginEnabled = false

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
