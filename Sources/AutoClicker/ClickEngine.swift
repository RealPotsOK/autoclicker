import AppKit
import AutoClickCore

/// Timers, taps, and UI callbacks all run on the main run loop.
final class ClickEngine {
    static let eventTag: Int64 = 0x4155544F434C494B
    private static let modifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
        .maskAlphaShift, .maskSecondaryFn, .maskHelp
    ]
    private(set) var state: ClickStateMachine
    private(set) var clickCount: UInt64 = 0
    var onChange: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var canClickAtPointer: (() -> Bool)?
    private var timer: DispatchSourceTimer?
    private var releaseWork: DispatchWorkItem?
    private var revision: UInt64 = 0
    private var injectedMouseDown = false
    private var injectedClickCount: Int64 = 1
    private var injectedModifiers: CGEventFlags = []
    private var lastClickPosition = CGPoint.zero
    private let eventSource = CGEventSource(stateID: .privateState)
    private let postEvent: (CGEvent) -> Void
    private let permissionCheck: () -> Bool
    private let readModifiers: () -> CGEventFlags

    init(configuration: ClickConfiguration,
         postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
         permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         readModifiers: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.hidSystemState) }) {
        state = ClickStateMachine(configuration: configuration)
        self.postEvent = postEvent
        self.permissionCheck = permissionCheck
        self.readModifiers = readModifiers
        eventSource?.userData = Self.eventTag
        eventSource?.localEventsSuppressionInterval = 0
    }

    func update(
        mode: ClickMode? = nil, mouseHeld: Bool? = nil,
        suspended: Bool? = nil, ready: Bool? = nil,
        configuration: ClickConfiguration? = nil, physicalClickCount: Int64 = 1,
        physicalModifiers: CGEventFlags? = nil
    ) {
        apply(state.update(mode: mode, mouseHeld: mouseHeld, suspended: suspended,
                           ready: ready, configuration: configuration), clickCount: physicalClickCount,
              modifiers: physicalModifiers)
        onChange?()
    }

    func releaseForwardedPress() {
        // Balance a physical mouse-down that reached the target before the mode was armed.
        postMouseEvent(.leftMouseUp, at: CGEvent(source: nil)?.location ?? .zero)
    }

    private func apply(_ actions: [ClickAction], clickCount: Int64 = 1, modifiers: CGEventFlags? = nil) {
        for action in actions {
            switch action {
            case .cancel: cancel()
            case .schedule(let delay): schedule(after: delay)
            case .click:
                guard state.isRunning, checkPermission() else { return }
                if canClickAtPointer?() ?? true { emitClick(clickCount: clickCount, modifiers: modifiers) }
            }
        }
    }

    private func schedule(after delay: TimeInterval) {
        timer?.cancel()
        let generation = revision
        let next = DispatchSource.makeTimerSource(queue: .main)
        next.schedule(deadline: .now() + delay, leeway: .microseconds(200))
        next.setEventHandler { [weak self] in
            guard let self, self.revision == generation else { return }
            self.timer?.cancel()
            self.timer = nil
            guard self.state.isRunning else { return }
            guard self.checkPermission() else { return }
            // Never generate clicks on our own menu bar button or an open settings panel.
            guard self.canClickAtPointer?() ?? true else {
                self.schedule(after: 0.05)
                return
            }
            self.apply(self.state.fire())
        }
        timer = next
        next.resume()
    }

    private func emitClick(clickCount: Int64, modifiers: CGEventFlags?) {
        releaseInjectedPress()
        lastClickPosition = CGEvent(source: nil)?.location ?? .zero
        // Physical double/triple-clicks retain their native count. Timer-driven clicks use 1.
        injectedClickCount = max(1, clickCount)
        // Use the real press's flags for an immediate click and fresh hardware flags for repeats.
        // Keep each down/up pair consistent if a modifier changes during the 5 ms press.
        injectedModifiers = (modifiers ?? readModifiers()).intersection(Self.modifierMask)
        injectedMouseDown = true
        postMouseEvent(.leftMouseDown, at: lastClickPosition, clickCount: injectedClickCount,
                       modifiers: injectedModifiers)
        self.clickCount &+= 1
        let work = DispatchWorkItem { [weak self] in self?.releaseInjectedPress() }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(5), execute: work)
    }

    private func checkPermission() -> Bool {
        guard permissionCheck() else {
            update(mode: .off, ready: false)
            onFailure?("Accessibility access was removed. Allow Auto Clicker in System Settings.")
            return false
        }
        return true
    }

    private func postMouseEvent(_ type: CGEventType, at point: CGPoint, clickCount: Int64 = 1,
                                modifiers: CGEventFlags? = nil) {
        guard let event = CGEvent(mouseEventSource: eventSource, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.setDoubleValueField(.mouseEventPressure, value: type == .leftMouseDown ? 1 : 0)
        event.flags = (modifiers ?? readModifiers()).intersection(Self.modifierMask)
        postEvent(event)
    }

    private func releaseInjectedPress() {
        releaseWork?.cancel()
        releaseWork = nil
        guard injectedMouseDown else { return }
        injectedMouseDown = false
        postMouseEvent(.leftMouseUp, at: CGEvent(source: nil)?.location ?? lastClickPosition,
                       clickCount: injectedClickCount, modifiers: injectedModifiers)
    }

    private func cancel() {
        revision &+= 1
        timer?.cancel()
        timer = nil
        releaseInjectedPress()
    }
}
