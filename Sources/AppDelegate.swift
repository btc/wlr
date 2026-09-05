import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var controller: FilterController!
    private var scheduler: Scheduler!
    private let hotKey = HotKey()
    private let prefs = Preferences.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfDuplicate() else { return }

        controller = FilterController()
        scheduler = Scheduler(controller: controller)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        updateStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged),
            name: FilterController.didChangeState, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateChanged),
            name: Preferences.didChange, object: nil
        )

        hotKey.register(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ) { [weak self] in
            self?.controller.toggle()
        }

        // Honour the schedule first, then paint without animating so there is no visible
        // un-filtered flash at login.
        scheduler.applyNow()
        controller.syncImmediately()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    /// LaunchAgent bootstrapping starts a second copy while one is already running.
    /// The newcomer exits rather than fighting over the LUT.
    private func terminateIfDuplicate() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        NSApp.terminate(nil)
        return true
    }

    @objc private func stateChanged() {
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let on = controller.isOn
        let symbol = on ? "moon.circle.fill" : "moon.circle"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "WLR") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = on ? "●" : "○"
        }
        button.toolTip = on ? "WLR: on" : "WLR: off"
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let on = controller.isOn

        menu.addItem(BlockMenuItem(
            title: on ? "Turn Off" : "Turn On",
            keyEquivalent: "r",
            modifiers: [.control, .option, .command]
        ) { [weak self] in
            self?.controller.toggle()
        })

        let status = NSMenuItem(
            title: on ? "Filtering — green and blue removed" : "Not filtering",
            action: nil, keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let intensityItem = NSMenuItem()
        intensityItem.view = SliderMenuItemView(
            title: "Blue / green removal", minValue: 0, maxValue: 1, value: prefs.intensity
        ) { [weak self] value in
            self?.prefs.intensity = value
        }
        menu.addItem(intensityItem)

        let redItem = NSMenuItem()
        redItem.view = SliderMenuItemView(
            title: "Red level",
            minValue: Preferences.minimumRedLevel,
            maxValue: 1,
            value: prefs.redLevel
        ) { [weak self] value in
            self?.prefs.redLevel = value
        }
        menu.addItem(redItem)

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Schedule — \(scheduler.statusDescription())"))

        menu.addItem(BlockMenuItem(
            title: "Manual only",
            state: prefs.schedule == .manual ? .on : .off
        ) { [weak self] in
            self?.prefs.schedule = .manual
        })
        menu.addItem(BlockMenuItem(
            title: "Fixed times…",
            state: prefs.schedule == .fixed ? .on : .off
        ) { [weak self] in
            self?.editFixedTimes()
        })
        menu.addItem(BlockMenuItem(
            title: "Sunset to sunrise…",
            state: prefs.schedule == .solar ? .on : .off
        ) { [weak self] in
            self?.editLocation()
        })

        menu.addItem(.separator())

        menu.addItem(BlockMenuItem(
            title: "Launch at Login",
            state: LoginItem.isEnabled ? .on : .off
        ) {
            LoginItem.setEnabled(!LoginItem.isEnabled)
        })
        menu.addItem(BlockMenuItem(title: "Restore Display Colors") { [weak self] in
            self?.controller.panicRestore()
        })

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "Quit WLR", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    // MARK: - Dialogs

    private func editFixedTimes() {
        NSApp.activate(ignoringOtherApps: true)

        let onPicker = timePicker(minutes: prefs.onMinutes)
        let offPicker = timePicker(minutes: prefs.offMinutes)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        let onLabel = NSTextField(labelWithString: "Turn on at")
        let offLabel = NSTextField(labelWithString: "Turn off at")
        for view in [onLabel, onPicker, offLabel, offPicker] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            onLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            onLabel.topAnchor.constraint(equalTo: container.topAnchor),
            onPicker.leadingAnchor.constraint(equalTo: onLabel.trailingAnchor, constant: 8),
            onPicker.centerYAnchor.constraint(equalTo: onLabel.centerYAnchor),

            offLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            offLabel.topAnchor.constraint(equalTo: onLabel.bottomAnchor, constant: 12),
            offLabel.widthAnchor.constraint(equalTo: onLabel.widthAnchor),
            offPicker.leadingAnchor.constraint(equalTo: offLabel.trailingAnchor, constant: 8),
            offPicker.centerYAnchor.constraint(equalTo: offLabel.centerYAnchor),
        ])

        let alert = NSAlert()
        alert.messageText = "Schedule"
        alert.informativeText = "WLR turns on and off at these times every day."
        alert.accessoryView = container
        alert.addButton(withTitle: "Use Schedule")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        prefs.onMinutes = minutes(from: onPicker)
        prefs.offMinutes = minutes(from: offPicker)
        prefs.schedule = .fixed
        scheduler.applyNow()
    }

    private func timePicker(minutes: Int) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        var components = DateComponents()
        components.hour = (((minutes % 1440) + 1440) % 1440) / 60
        components.minute = (((minutes % 1440) + 1440) % 1440) % 60
        components.year = 2000
        components.month = 1
        components.day = 1
        picker.dateValue = Calendar.current.date(from: components) ?? Date()
        return picker
    }

    private func minutes(from picker: NSDatePicker) -> Int {
        let components = Calendar.current.dateComponents(
            [.hour, .minute], from: picker.dateValue)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func editLocation() {
        NSApp.activate(ignoringOtherApps: true)

        let latField = NSTextField(string: String(format: "%.4f", prefs.latitude))
        let lonField = NSTextField(string: String(format: "%.4f", prefs.longitude))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        let latLabel = NSTextField(labelWithString: "Latitude")
        let lonLabel = NSTextField(labelWithString: "Longitude")
        for view in [latLabel, latField, lonLabel, lonField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            latLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            latLabel.topAnchor.constraint(equalTo: container.topAnchor),
            latField.leadingAnchor.constraint(equalTo: latLabel.trailingAnchor, constant: 8),
            latField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            latField.centerYAnchor.constraint(equalTo: latLabel.centerYAnchor),

            lonLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lonLabel.topAnchor.constraint(equalTo: latLabel.bottomAnchor, constant: 12),
            lonLabel.widthAnchor.constraint(equalTo: latLabel.widthAnchor),
            lonField.leadingAnchor.constraint(equalTo: lonLabel.trailingAnchor, constant: 8),
            lonField.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lonField.centerYAnchor.constraint(equalTo: lonLabel.centerYAnchor),
        ])

        let alert = NSAlert()
        alert.messageText = "Sunset to Sunrise"
        alert.informativeText =
            "Sun times are computed locally from these coordinates. Nothing is sent anywhere "
            + "and Location Services is not used."
        alert.accessoryView = container
        alert.addButton(withTitle: "Use Schedule")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let lat = Double(latField.stringValue), lat >= -90, lat <= 90 {
            prefs.latitude = lat
        }
        if let lon = Double(lonField.stringValue), lon >= -180, lon <= 180 {
            prefs.longitude = lon
        }
        prefs.schedule = .solar
        scheduler.applyNow()
    }
}
