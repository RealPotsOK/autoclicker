import AppKit

final class MouseMonitor {
    var onPhysicalChange: ((Bool, Int64, CGEventFlags?) -> Void)?
    var shouldCapture: ((CGPoint) -> Bool)?
    var onInterruption: (() -> Void)?
    private(set) var physicalMouseDown = false
    private(set) var capturedPress = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isInstalled: Bool { eventTap != nil }

    func start() -> Bool {
        guard eventTap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<MouseMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        eventTap = tap
        runLoopSource = source
        physicalMouseDown = CGEventSource.buttonState(.hidSystemState, button: .left)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        onPhysicalChange?(physicalMouseDown, 1, nil)
        return true
    }

    /// Called when a shortcut arms the app in the middle of an existing physical press.
    func captureExistingPress() -> Bool {
        guard physicalMouseDown, !capturedPress else { return false }
        capturedPress = true
        return true
    }

    func synchronizePhysicalState() {
        // Session-level synthetic clicks never enter the HID state. Recover from a missed
        // physical release during sleep, a locked session, or a disabled event tap.
        let held = CGEventSource.buttonState(.hidSystemState, button: .left)
        if !held { capturedPress = false }
        if physicalMouseDown != held {
            physicalMouseDown = held
            onPhysicalChange?(held, 1, nil)
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        physicalMouseDown = false
        capturedPress = false
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            onInterruption?()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Injected up/down events must never change whether the real button is held.
        guard event.getIntegerValueField(.eventSourceUserData) != ClickEngine.eventTag else {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .leftMouseDown:
            physicalMouseDown = true
            capturedPress = shouldCapture?(event.location) ?? false
            onPhysicalChange?(true, event.getIntegerValueField(.mouseEventClickState), event.flags)
            return capturedPress ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp:
            let captured = capturedPress
            physicalMouseDown = false
            capturedPress = false
            onPhysicalChange?(false, event.getIntegerValueField(.mouseEventClickState), event.flags)
            return captured ? nil : Unmanaged.passUnretained(event)
        case .leftMouseDragged where capturedPress:
            // Keep pointer motion without turning the physical hold into a drag in the target app.
            event.type = .mouseMoved
            event.setDoubleValueField(.mouseEventPressure, value: 0)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
