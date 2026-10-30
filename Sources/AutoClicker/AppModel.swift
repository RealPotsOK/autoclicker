import AppKit
import AutoClickCore
import Combine
import ServiceManagement

final class AppModel: ObservableObject {
    @Published private(set) var configuration: ClickConfiguration
    @Published private(set) var mode: ClickMode = .off
    @Published private(set) var isMouseHeld = false
    @Published private(set) var isReady = false
    @Published private(set) var isSuspended = false
    @Published private(set) var clickCount: UInt64 = 0
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published var message: String?
    @Published var shortcutError: String?
    var onStateChange: (() -> Void)?
    var onShowControls: (() -> Void)?
    var pointerIsOverControls: (() -> Bool)?
    let engine: ClickEngine
    private let mouse = MouseMonitor()
    private let defaults: UserDefaults
    private let isPreview: Bool
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private static let configurationKey = "clickConfiguration"

    init(preview: Bool = false, defaults: UserDefaults = .standard) {
        isPreview = preview
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.configurationKey)
            .flatMap { try? JSONDecoder().decode(ClickConfiguration.self, from: $0) }
        let settings = (preview ? ClickConfiguration() : saved ?? .init()).validated
        configuration = settings
        engine = ClickEngine(configuration: settings)
        engine.onChange = { [weak self] in self?.publishState() }
        engine.onFailure = { [weak self] message in self?.message = message }
        engine.canClickAtPointer = { [weak self] in !(self?.pointerIsOverControls?() ?? false) }
        mouse.onPhysicalChange = { [weak self] held, clickCount, modifiers in
            self?.engine.update(mouseHeld: held, physicalClickCount: clickCount,
                                physicalModifiers: modifiers)
        }
        mouse.shouldCapture = { [weak self] _ in
            guard let self else { return false }
            return self.mode != .off && self.isReady && !self.isSuspended
                && !(self.pointerIsOverControls?() ?? false)
        }
        mouse.onInterruption = { [weak self] in
            self?.engine.update(mode: .off)
            self?.message = "macOS interrupted mouse access. Clicking has stopped; use a start shortcut to resume."
        }
        if preview {
            launchAtLogin = true
            engine.update(suspended: true, ready: true)
        }
    }

    func start() {
        guard !isPreview else { return }
        refreshSystemState()
        if !defaults.bool(forKey: "hasConfiguredLogin") {
            setLaunchAtLogin(true)
            defaults.set(true, forKey: "hasConfiguredLogin")
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshSystemState()
        }
        for notification in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: notification, object: nil, queue: .main
            ) { [weak self] _ in self?.selectMode(.off) })
        }
    }

    func selectMode(_ requestedMode: ClickMode) {
        guard requestedMode == .off || isReady else {
            onShowControls?()
            return
        }
        message = nil
        if requestedMode != .off { mouse.synchronizePhysicalState() }
        if requestedMode != .off, !isSuspended,
           !(pointerIsOverControls?() ?? false), mouse.captureExistingPress() {
            engine.releaseForwardedPress()
        }
        engine.update(mode: requestedMode, mouseHeld: mouse.physicalMouseDown)
    }

    func setSuspended(_ value: Bool) {
        engine.update(suspended: value)
    }

    func updateConfiguration(_ edit: (inout ClickConfiguration) -> Void) {
        var updated = configuration
        edit(&updated)
        updated = updated.validated
        guard updated != configuration else { return }
        configuration = updated
        if !isPreview, let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.configurationKey)
        }
        engine.update(configuration: updated)
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isPreview else { launchAtLogin = enabled; return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            message = "Could not change launch at login: \(error.localizedDescription)"
        }
    }

    func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func shutdown() {
        engine.update(mode: .off, ready: false)
        mouse.stop()
        refreshTimer?.invalidate()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private func publishState() {
        if mode != engine.state.mode { mode = engine.state.mode }
        if isMouseHeld != engine.state.isMouseHeld { isMouseHeld = engine.state.isMouseHeld }
        if isReady != engine.state.isReady { isReady = engine.state.isReady }
        if isSuspended != engine.state.isSuspended { isSuspended = engine.state.isSuspended }
        onStateChange?()
    }

    private func refreshSystemState() {
        let trusted = AXIsProcessTrusted()
        if trusted && !mouse.isInstalled {
            if mouse.start() {
                message = nil
                engine.update(mouseHeld: mouse.physicalMouseDown, ready: true)
            } else {
                message = "Mouse access could not start. Check Accessibility permission, then quit and reopen Auto Clicker."
            }
        } else if !trusted && isReady {
            engine.update(mode: .off, ready: false)
            mouse.stop()
        }
        if clickCount != engine.clickCount { clickCount = engine.clickCount }
        refreshLoginStatus()
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled || status == .requiresApproval
        if launchAtLogin != enabled { launchAtLogin = enabled }
        if loginNeedsApproval != (status == .requiresApproval) { loginNeedsApproval = status == .requiresApproval }
    }

    var statusTitle: String {
        if !isReady { return "Permission needed" }
        switch mode {
        case .off: return "Clicking is off"
        case .hold: return isMouseHeld ? "Hold mode active" : "Ready when you are"
        case .continuous: return "Continuous mode active"
        }
    }

    var statusDetail: String {
        if !isReady { return "Allow Accessibility to enable clicks and mouse detection." }
        switch mode {
        case .off: return "Choose a mode or use a keyboard shortcut."
        case .hold: return "Hold the left mouse button to auto click."
        case .continuous: return "Clicks resume when you close this panel."
        }
    }
}
