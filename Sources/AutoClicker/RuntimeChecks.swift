import AppKit
import AutoClickCore
import Carbon

/// Exercises the native adapters with an in-memory event sink. Never clicks another application.
enum RuntimeChecks {
    static func run() -> Int32 {
        var failures: [String] = []
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { failures.append(name); print("FAIL: \(name)") }
        }
        func drain(_ duration: TimeInterval) {
            let deadline = Date().addingTimeInterval(duration)
            while Date() < deadline {
                _ = RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.002)))
            }
        }

        var events: [CGEvent] = []
        let engine = ClickEngine(
            configuration: .init(clickDelayMilliseconds: 30, startDelayMilliseconds: 20),
            postEvent: { if let event = $0.copy() { events.append(event) } },
            permissionCheck: { true }, readModifiers: { [] }
        )
        engine.update(mode: .hold, ready: true)
        drain(0.04)
        check(events.isEmpty, "Hold mode waits for a physical press")
        engine.update(mouseHeld: true)
        check(events.map(\.type) == [.leftMouseDown], "A physical hold clicks immediately before any delay")
        drain(0.01)
        check(events.filter { $0.type == .leftMouseDown }.count == 1, "Repeating clicks wait through the start delay")
        drain(0.11)
        check(events.filter { $0.type == .leftMouseDown }.count >= 2, "A hold produces repeated clicks")
        engine.update(mouseHeld: false)
        let countAtRelease = events.count
        drain(0.07)
        check(events.count == countAtRelease, "Release cancels every queued click")
        check(events.filter { $0.type == .leftMouseDown }.count == events.filter { $0.type == .leftMouseUp }.count,
              "Every injected press is released")
        check(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == ClickEngine.eventTag },
              "All generated events carry the synthetic event tag")
        check(events.allSatisfy { $0.flags.isEmpty }, "Clicks are unmodified when no modifier keys are held")

        events.removeAll()
        engine.update(mouseHeld: true)
        engine.update(mouseHeld: false)
        drain(0.06)
        check(events.map(\.type) == [.leftMouseDown, .leftMouseUp],
              "A quick tap makes exactly one complete click without repeating")

        events.removeAll()
        engine.update(mode: .continuous)
        drain(0.09)
        check(events.contains { $0.type == .leftMouseDown }, "Continuous mode clicks with M1 released")
        engine.update(mode: .off)
        let countAtStop = events.count
        drain(0.07)
        check(events.count == countAtStop, "Off cancels continuous mode")

        events.removeAll()
        engine.update(mode: .continuous, suspended: true)
        drain(0.05)
        check(events.isEmpty, "The settings panel suspends timers")
        engine.update(suspended: false)
        drain(0.06)
        check(!events.isEmpty, "Closing the panel resumes the armed mode")
        engine.update(mode: .off)

        events.removeAll()
        engine.canClickAtPointer = { false }
        engine.update(mode: .continuous)
        drain(0.09)
        check(events.isEmpty, "The app never clicks its own menu bar controls")
        engine.update(mode: .off)
        engine.update(mode: .hold, mouseHeld: false)
        engine.update(mouseHeld: true)
        check(events.isEmpty, "An immediate hold click cannot target the app's own controls")
        engine.update(mode: .off, mouseHeld: false)

        var permission = true
        var protectedEvents = 0
        let protectedEngine = ClickEngine(
            configuration: .init(startDelayMilliseconds: 20), postEvent: { _ in protectedEvents += 1 },
            permissionCheck: { permission }
        )
        protectedEngine.update(mode: .continuous, ready: true)
        permission = false
        drain(0.05)
        check(protectedEvents == 0 && protectedEngine.state.mode == .off,
              "Permission loss turns off the engine before posting events")
        permission = true
        protectedEngine.update(mode: .hold, mouseHeld: false, ready: true)
        permission = false
        protectedEngine.update(mouseHeld: true)
        check(protectedEvents == 0 && protectedEngine.state.mode == .off,
              "The immediate hold click also checks permission before posting")

        let monitor = MouseMonitor()
        var physicalChanges: [Bool] = []
        monitor.onPhysicalChange = { held, _, _ in physicalChanges.append(held) }
        monitor.shouldCapture = { _ in true }
        let realDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                              mouseCursorPosition: .zero, mouseButton: .left)!
        let realUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                            mouseCursorPosition: .zero, mouseButton: .left)!
        check(monitor.handle(type: .leftMouseDown, event: realDown) == nil && monitor.physicalMouseDown,
              "An armed physical press is captured")
        let syntheticUp = realUp.copy()!
        syntheticUp.setIntegerValueField(.eventSourceUserData, value: ClickEngine.eventTag)
        _ = monitor.handle(type: .leftMouseUp, event: syntheticUp)
        check(monitor.physicalMouseDown && physicalChanges == [true],
              "Synthetic mouse-up cannot end a physical hold")
        let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                           mouseCursorPosition: .zero, mouseButton: .left)!
        check(monitor.handle(type: .leftMouseDragged, event: drag)?.takeUnretainedValue().type == .mouseMoved,
              "Captured holds preserve movement without dragging")
        check(monitor.handle(type: .leftMouseUp, event: realUp) == nil && !monitor.physicalMouseDown,
              "The real mouse-up immediately ends the hold")
        check(physicalChanges == [true, false], "Only real presses change physical hold state")

        var gestureEvents: [CGEvent] = []
        let gestureEngine = ClickEngine(
            configuration: .init(clickDelayMilliseconds: 30, startDelayMilliseconds: 60),
            postEvent: { if let event = $0.copy() { gestureEvents.append(event) } },
            permissionCheck: { true }
        )
        let gestureMonitor = MouseMonitor()
        gestureMonitor.shouldCapture = { _ in true }
        gestureMonitor.onPhysicalChange = { held, clickCount, modifiers in
            gestureEngine.update(mouseHeld: held, physicalClickCount: clickCount, physicalModifiers: modifiers)
        }
        gestureEngine.update(mode: .hold, ready: true)

        func physicalClick(_ type: CGEventType, count: Int64) {
            let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                mouseCursorPosition: .zero, mouseButton: .left)!
            event.setIntegerValueField(.mouseEventClickState, value: count)
            _ = gestureMonitor.handle(type: type, event: event)
        }

        physicalClick(.leftMouseDown, count: 1)
        physicalClick(.leftMouseUp, count: 1)
        physicalClick(.leftMouseDown, count: 2)
        physicalClick(.leftMouseUp, count: 2)
        check(gestureEvents.map { $0.getIntegerValueField(.mouseEventClickState) } == [1, 1, 2, 2],
              "Manual double-click counts survive the mouse monitor and click engine")
        check(gestureEvents.compactMap { NSEvent(cgEvent: $0)?.clickCount } == [1, 1, 2, 2],
              "AppKit recognizes the second manual click as a double-click")
        physicalClick(.leftMouseDown, count: 3)
        physicalClick(.leftMouseUp, count: 3)
        check(gestureEvents.suffix(2).compactMap { NSEvent(cgEvent: $0)?.clickCount } == [3, 3],
              "Triple-clicks preserve matching mouse-down and mouse-up counts")
        let countAfterGestures = gestureEvents.count
        drain(0.08)
        check(gestureEvents.count == countAfterGestures, "Quick manual gestures cancel the start delay without extra clicks")

        gestureEvents.removeAll()
        physicalClick(.leftMouseDown, count: 2)
        drain(0.11)
        physicalClick(.leftMouseUp, count: 2)
        let repeatedClickCounts = gestureEvents.filter { $0.type == .leftMouseDown }
            .map { $0.getIntegerValueField(.mouseEventClickState) }
        check(repeatedClickCounts.count >= 2 && repeatedClickCounts.first == 2
                && repeatedClickCounts.dropFirst().allSatisfy { $0 == 1 },
              "Automatic clicks remain single clicks after a manual double-click")
        check(gestureEvents.count.isMultiple(of: 2)
                && stride(from: 0, to: gestureEvents.count - 1, by: 2).allSatisfy {
                    gestureEvents[$0].getIntegerValueField(.mouseEventClickState)
                        == gestureEvents[$0 + 1].getIntegerValueField(.mouseEventClickState)
                }, "Each generated mouse-up keeps its own mouse-down's click count")
        gestureEngine.update(mode: .off)

        checkModifierClicks(check: check, drain: drain)

        let shortcuts = GlobalHotKeys()
        var modes: [ClickMode] = []
        shortcuts.onMode = { modes.append($0) }
        if let error = shortcuts.register() {
            check(false, "Global shortcuts register: \(error) (quit the running copy before self-test)")
        } else {
            check(true, "All four global shortcuts register")
            for id in UInt32(1)...4 {
                var event: EventRef?
                let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                          GetCurrentEventTime(), UInt32(kEventAttributeNone), &event)
                guard created == noErr, let event else { check(false, "Create hotkey event"); continue }
                var identity = EventHotKeyID(signature: GlobalHotKeys.signature, id: id)
                let parameter = SetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identity)
                check(parameter == noErr && SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr,
                      "Shortcut \(id) reaches the Carbon handler")
                ReleaseEvent(event)
            }
            check(modes == [.hold, .continuous, .off, .off], "Start shortcuts replace modes and both stop shortcuts turn off")
        }
        shortcuts.unregister()
        print("\(checks - failures.count)/\(checks) native runtime checks passed. No global mouse events were posted.")
        return failures.isEmpty ? 0 : 1
    }

    private static func checkModifierClicks(check: (Bool, String) -> Void, drain: (TimeInterval) -> Void) {
        var events: [CGEvent] = []
        let engine = ClickEngine(
            configuration: .init(startDelayMilliseconds: 1000),
            postEvent: { if let event = $0.copy() { events.append(event) } },
            permissionCheck: { true }, readModifiers: { [] }
        )
        let monitor = MouseMonitor()
        monitor.shouldCapture = { _ in true }
        monitor.onPhysicalChange = { held, count, modifiers in
            engine.update(mouseHeld: held, physicalClickCount: count, physicalModifiers: modifiers)
        }
        engine.update(mode: .hold, ready: true)

        func physicalClick(_ type: CGEventType, flags: CGEventFlags, count: Int64 = 1) {
            let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                mouseCursorPosition: .zero, mouseButton: .left)!
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState, value: count)
            _ = monitor.handle(type: type, event: event)
        }

        let modifiers: [(String, CGEventFlags)] = [
            ("Shift", .maskShift), ("Control", .maskControl), ("Option", .maskAlternate),
            ("Command", .maskCommand), ("Caps Lock", .maskAlphaShift),
            ("Fn", .maskSecondaryFn), ("Help", .maskHelp)
        ]
        for (name, flag) in modifiers {
            events.removeAll()
            physicalClick(.leftMouseDown, flags: flag)
            physicalClick(.leftMouseUp, flags: [])
            check(events.count == 2 && events.allSatisfy { $0.flags == flag },
                  "\(name)-click preserves the physical press's modifiers on mouse-down and mouse-up")
        }

        events.removeAll()
        let combination: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        physicalClick(.leftMouseDown, flags: combination, count: 2)
        physicalClick(.leftMouseUp, flags: [], count: 2)
        check(events.count == 2 && events.allSatisfy {
            $0.flags == combination && $0.getIntegerValueField(.mouseEventClickState) == 2
        }, "Modifier combinations preserve manual double-click counts")
        let expectedAppKit: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]
        check(events.compactMap { NSEvent(cgEvent: $0)?.modifierFlags } == [expectedAppKit, expectedAppKit],
              "AppKit receives all held modifiers on manual clicks")

        events.removeAll()
        physicalClick(.leftMouseDown, flags: [.maskShift, .maskNonCoalesced, .maskNumericPad])
        physicalClick(.leftMouseUp, flags: [])
        check(events.count == 2 && events.allSatisfy { $0.flags == .maskShift },
              "Only keyboard modifiers are copied into generated clicks")
        engine.update(mode: .off)

        var hardwareFlags: CGEventFlags = .maskShift
        var releaseAfterNextDown = true
        var repeatingEvents: [CGEvent] = []
        let repeatingEngine = ClickEngine(
            configuration: .init(clickDelayMilliseconds: 30, startDelayMilliseconds: 0),
            postEvent: { event in
                if let event = event.copy() { repeatingEvents.append(event) }
                // Simulate releasing Shift between the first down and its delayed up.
                if event.type == .leftMouseDown && releaseAfterNextDown {
                    hardwareFlags = []
                    releaseAfterNextDown = false
                }
            }, permissionCheck: { true }, readModifiers: { hardwareFlags }
        )
        repeatingEngine.update(mode: .continuous, ready: true)
        drain(0.08)
        let downs = repeatingEvents.filter { $0.type == .leftMouseDown }
        check(downs.count >= 2 && downs.first?.flags == .maskShift
                && downs.dropFirst().allSatisfy { $0.flags.isEmpty },
              "Continuous clicks stop using Shift as soon as it is released")
        check(repeatingEvents.count >= 2 && repeatingEvents[0].flags == .maskShift
                && repeatingEvents[1].type == .leftMouseUp && repeatingEvents[1].flags == .maskShift,
              "Releasing a modifier during a generated click does not split its down/up pair")

        let countBeforePress = repeatingEvents.count
        hardwareFlags = combination
        drain(0.07)
        let clicksAfterPress = repeatingEvents.dropFirst(countBeforePress).filter { $0.type == .leftMouseDown }
        check(!clicksAfterPress.isEmpty && clicksAfterPress.allSatisfy { $0.flags == combination },
              "Pressing modifiers during continuous clicking applies them to the next clicks")

        repeatingEngine.update(mode: .off)
        repeatingEvents.removeAll()
        hardwareFlags = combination
        releaseAfterNextDown = true
        repeatingEngine.update(mode: .hold, mouseHeld: false)
        repeatingEngine.update(mouseHeld: true)
        drain(0.08)
        repeatingEngine.update(mouseHeld: false)
        let heldDowns = repeatingEvents.filter { $0.type == .leftMouseDown }
        check(heldDowns.count >= 2 && heldDowns.first?.flags == combination
                && heldDowns.dropFirst().allSatisfy { $0.flags.isEmpty },
              "Hold-mode automatic clicks refresh modifiers instead of latching the first click's keys")
        check(repeatingEvents.count.isMultiple(of: 2)
                && stride(from: 0, to: repeatingEvents.count - 1, by: 2).allSatisfy {
                    repeatingEvents[$0].flags == repeatingEvents[$0 + 1].flags
                }, "Stopping a modified click always releases it with matching modifier flags")

        repeatingEvents.removeAll()
        hardwareFlags = .maskControl
        repeatingEngine.releaseForwardedPress()
        check(repeatingEvents.count == 1 && repeatingEvents[0].type == .leftMouseUp
                && repeatingEvents[0].flags == .maskControl,
              "Balancing a physical press also respects held modifiers")
        repeatingEngine.update(mode: .off)
    }
}
