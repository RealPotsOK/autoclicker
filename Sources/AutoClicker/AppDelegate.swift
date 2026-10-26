import AppKit
import AutoClickCore
import SwiftUI
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let shortcuts = GlobalHotKeys()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var openObserver: NSObjectProtocol?
    private var diagnosticObserver: NSObjectProtocol?
    private var terminationSignals: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            terminationSignals.append(source)
        }
        configureEditingMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleControls)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("Auto Clicker menu")
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let controller = NSHostingController(rootView: ControlsView(model: model) { [weak self] in
            self?.popover.performClose(nil)
        })
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
        model.onStateChange = { [weak self] in self?.updateStatusItem() }
        model.onShowControls = { [weak self] in self?.showControls() }
        model.pointerIsOverControls = { [weak self] in self?.pointerIsOverControls() ?? false }
        shortcuts.onMode = { [weak self] mode in
            guard let self else { return }
            if mode != .off { self.popover.performClose(nil) }
            self.model.selectMode(mode)
        }
        model.shortcutError = shortcuts.register()
        model.start()
        updateStatusItem()
        openObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.kevin.autoclicker.showControls"), object: nil, queue: .main
        ) { [weak self] _ in self?.showControls() }
        diagnosticObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.kevin.autoclicker.diagnose"), object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let request = notification.object as? String else { return }
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("local.kevin.autoclicker.diagnosticResponse"), object: request,
                userInfo: ["processIdentifier": ProcessInfo.processInfo.processIdentifier,
                           "mode": self.model.mode.rawValue, "mouseAccessReady": self.model.isReady,
                           "pausedForControls": self.model.isSuspended,
                           "shortcutError": self.model.shortcutError ?? "none"], deliverImmediately: true
            )
        }
        if !model.isReady || model.shortcutError != nil || model.message != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showControls() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcuts.unregister()
        model.shutdown()
        if let openObserver { DistributedNotificationCenter.default().removeObserver(openObserver) }
        if let diagnosticObserver { DistributedNotificationCenter.default().removeObserver(diagnosticObserver) }
    }

    func popoverWillShow(_ notification: Notification) { model.setSuspended(true) }

    func popoverWillClose(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        NSApp.hide(nil)
        model.setSuspended(false)
    }

    @objc private func toggleControls() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showControls()
        }
    }

    private func showControls() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        model.setSuspended(true)
        let menu = NSMenu()
        let stop = NSMenuItem(title: "Stop Clicking", action: #selector(stopClicking), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Auto Clicker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        }
        if !popover.isShown { model.setSuspended(false) }
    }

    @objc private func stopClicking() { model.selectMode(.off) }
    @objc private func openSettings() { showControls() }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let active = model.mode != .off
        button.image = NSImage(systemSymbolName: active ? "cursorarrow.click" : "cursorarrow", accessibilityDescription: nil)
        button.image?.isTemplate = true
        button.title = model.mode == .hold ? " H" : model.mode == .continuous ? " ∞" : ""
        let mode = model.mode == .hold ? "Hold M1 to click" : model.mode == .continuous ? "Continuous clicking" : "Off"
        button.toolTip = "Auto Clicker — \(mode)\n⌘ Page Up: Hold · ⌘ ⇧ Page Up: Continuous\n⌘ Page Down: Stop"
    }

    private func pointerIsOverControls() -> Bool {
        if popover.isShown { return true }
        guard let button = statusItem?.button, let window = button.window else { return false }
        // AppKit mouse and window coordinates share the same screen space, including multiple displays.
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil)).insetBy(dx: -6, dy: -3)
        return frame.contains(NSEvent.mouseLocation)
    }

    private func configureEditingMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Auto Clicker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                    ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
