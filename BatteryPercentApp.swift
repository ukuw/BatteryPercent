import SwiftUI
import IOKit.ps
import ServiceManagement // for SMAppService (launch at login)

@main
struct BatteryPercentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings {
            EmptyView() // no visible window
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
        // Sync battery saver state from system on launch
        let sysBatterySaver = currentLowPowerModeState()
        if sysBatterySaver != batterySaverEnabled {
            UserDefaults.standard.set(sysBatterySaver, forKey: kBatterySaverKey)
        }

        setupMenu()
        updateBattery()

        // Also observe LPM changes from outside the app (Notification Center)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name(rawValue: "com.apple.system.lowpowermode"),
            object: nil
        )

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
            // Left click: no action
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

        // --- Battery section header ---
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
        chargeLimitItem.toolTip = "Uses the 'battery' CLI (actuallymentor/battery) to cap charging at 80%. Requires installation on first use."
        statusMenu.addItem(chargeLimitItem)

        // Battery Saver (Low Power Mode)
        let lpmState = currentLowPowerModeState()
        let batterySaverItem = NSMenuItem(
            title: "Battery Saver (Low Power Mode)",
            action: #selector(toggleBatterySaver(_:)),
            keyEquivalent: ""
        )
        batterySaverItem.state = lpmState ? .on : .off
        batterySaverItem.target = self
        batterySaverItem.toolTip = "Toggles macOS Low Power Mode. Creates a sudoers rule at /private/etc/sudoers.d/lowpowermode on first use so no password is needed."
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

    // MARK: - LPM state observer

    @objc private func powerStateChanged(_ notification: Notification) {
        let lpmState = currentLowPowerModeState()
        UserDefaults.standard.set(lpmState, forKey: kBatterySaverKey)
        setupMenu() // refresh checkmarks
    }

    // MARK: - Charging Limit via 'battery' CLI (actuallymentor/battery)
    // Repo: https://github.com/actuallymentor/battery
    // Install: curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
    // Usage:   battery maintain 80   /   battery maintain stop

    private func isBatteryCLIInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: "/usr/local/bin/battery")
    }

    private func installBatteryCLI() {
        // Runs the one-line installer from actuallymentor/battery via privileged shell
        let script = """
        do shell script "curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            NSLog("BatteryPercent: battery CLI install failed: %@", err)
        }
    }

    private func applyChargeLimit(_ enable: Bool) {
        if enable {
            if !isBatteryCLIInstalled() {
                // Prompt user before installing
                let alert = NSAlert()
                alert.messageText = "Install 'battery' CLI?"
                alert.informativeText = "Limiting charging to 80% requires the 'battery' command-line tool by actuallymentor. It will be downloaded and installed now (requires admin password)."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Install")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                guard response == .alertFirstButtonReturn else {
                    // User cancelled – revert pref
                    UserDefaults.standard.set(false, forKey: kChargeLimit80Key)
                    setupMenu()
                    return
                }
                installBatteryCLI()
            }
            runPrivileged("/usr/local/bin/battery maintain 80")
        } else {
            if isBatteryCLIInstalled() {
                runPrivileged("/usr/local/bin/battery maintain stop")
            }
        }
    }

    // MARK: - Low Power Mode via sudoers + pmset
    // Method: create /private/etc/sudoers.d/lowpowermode on first use,
    // then use sudo pmset to toggle LPM without password.
    // Approach mirrors https://github.com/nift4/BatterySaverToggle

    private let sudoersPath = "/private/etc/sudoers.d/lowpowermode"
    private let sudoersRule = "ALL ALL=(ALL) NOPASSWD: /usr/bin/pmset -a lowpowermode *\n"

    private func ensureSudoersRule() {
        guard !FileManager.default.fileExists(atPath: sudoersPath) else { return }

        // Write sudoers rule via privileged AppleScript (one-time setup)
        // The rule allows anyone on the machine to change LPM state only
        let rule = sudoersRule
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
        do shell script "echo -n \\\"\\(rule)\\\" | sudo tee /private/etc/sudoers.d/lowpowermode > /dev/null && sudo chmod 440 /private/etc/sudoers.d/lowpowermode" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            NSLog("BatteryPercent: sudoers setup failed: %@", err)
        }
    }

    private func applyBatterySaver(_ enable: Bool) {
        ensureSudoersRule()
        let flag = enable ? "1" : "0"
        // Use privileged AppleScript to avoid "Operation not permitted" from Process()
        runPrivileged("sudo /usr/bin/pmset -a lowpowermode \(flag)")
        setupMenu() // refresh checkmark to reflect real state
    }

    /// Reads the actual current Low Power Mode state from pmset (read-only, no privilege needed)
    private func currentLowPowerModeState() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("lowpowermode              1")
    }

    // MARK: - Privileged shell runner via NSAppleScript
    // Avoids "Operation not permitted" when spawning /bin/bash or /usr/bin/sudo
    // directly via Process() under Hardened Runtime / App Sandbox.

    private func runPrivileged(_ command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            NSLog("BatteryPercent: privileged shell failed: %@", err)
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
            // If this fails, just quit
        }
        NSApp.terminate(self)
    }

    @objc private func quitApp() {
        NSApp.terminate(self)
    }

    // MARK: - Battery

    @objc func updateBattery() {
        let (percentage, isCharging, isPlugged) = getBatteryState()
        var title = "\(percentage)%"
        // Show charging/plugged indicator only when NOT running on battery.
        // No emoji, no icon – plain text only.
        if isCharging {
            title += " (Charging)"
        } else if isPlugged {
            title += " (Plugged in)"
        }
        // On battery: percentage only, no indicator appended
        statusItem.button?.title = title
    }

    /// Returns (percentage, isCharging, isPluggedIn)
    private func getBatteryState() -> (Int, Bool, Bool) {
        guard
            let snapshot    = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources     = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source      = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?
                                .takeUnretainedValue() as? [String: Any],
            let capacity    = description[kIOPSCurrentCapacityKey as String] as? Int,
            let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
            maxCapacity > 0
        else {
            return (100, false, false)
        }

        let percent     = Swift.max(0, Swift.min(100, Int((Double(capacity) / Double(maxCapacity)) * 100.0)))

        // kIOPSPowerSourceStateKey: "AC Power" = plugged in, "Battery Power" = on battery
        let powerSource = description[kIOPSPowerSourceStateKey as String] as? String ?? ""
        let isPlugged   = (powerSource == kIOPSACPowerValue as String)

        // kIOPSIsChargingKey: true when actively charging
        let isCharging  = (description[kIOPSIsChargingKey as String] as? Bool) ?? false

        return (percent, isCharging, isPlugged)
    }
}
