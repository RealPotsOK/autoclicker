import Foundation

public enum ClickMode: String, Codable, CaseIterable {
    case off, hold, continuous
}

public struct ClickConfiguration: Codable, Equatable {
    public var clickDelayMilliseconds: Double
    public var clicksPerBurst: Int
    public var burstPauseMilliseconds: Double
    public var startDelayMilliseconds: Double

    public init(
        clickDelayMilliseconds: Double = 100,
        clicksPerBurst: Int = 1,
        burstPauseMilliseconds: Double = 0,
        startDelayMilliseconds: Double = 1000
    ) {
        self.clickDelayMilliseconds = clickDelayMilliseconds
        self.clicksPerBurst = clicksPerBurst
        self.burstPauseMilliseconds = burstPauseMilliseconds
        self.startDelayMilliseconds = startDelayMilliseconds
    }

    public var validated: Self {
        var result = self
        result.clickDelayMilliseconds = Self.clamp(clickDelayMilliseconds, 10...60_000, fallback: 100)
        result.clicksPerBurst = min(1000, max(1, clicksPerBurst))
        result.burstPauseMilliseconds = Self.clamp(burstPauseMilliseconds, 0...3_600_000, fallback: 0)
        result.startDelayMilliseconds = Self.clamp(startDelayMilliseconds, 0...3_600_000, fallback: 1000)
        return result
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

public enum ClickAction: Equatable {
    case cancel
    case schedule(after: TimeInterval)
    case click
}

/// All transitions are synchronous. The macOS adapter owns timers and event delivery.
public struct ClickStateMachine {
    public private(set) var mode: ClickMode = .off
    public private(set) var isMouseHeld = false
    public private(set) var isSuspended = false
    public private(set) var isReady = false
    public private(set) var configuration: ClickConfiguration
    public private(set) var clicksInBurst = 0

    public init(configuration: ClickConfiguration = .init()) {
        self.configuration = configuration.validated
    }

    public var isRunning: Bool {
        isReady && !isSuspended && (mode == .continuous || (mode == .hold && isMouseHeld))
    }

    public mutating func update(
        mode: ClickMode? = nil,
        mouseHeld: Bool? = nil,
        suspended: Bool? = nil,
        ready: Bool? = nil,
        configuration: ClickConfiguration? = nil
    ) -> [ClickAction] {
        let wasRunning = isRunning
        let wasMouseHeld = isMouseHeld
        let wasArmedForHold = self.mode == .hold && isReady && !isSuspended
        let previousMode = self.mode
        let previousConfiguration = self.configuration
        if let mode { self.mode = mode }
        if let mouseHeld { isMouseHeld = mouseHeld }
        if let suspended { isSuspended = suspended }
        if let ready { isReady = ready }
        if let configuration { self.configuration = configuration.validated }

        guard isRunning else {
            clicksInBurst = 0
            return [.cancel]
        }
        if wasArmedForHold && self.mode == .hold && !wasMouseHeld && isMouseHeld {
            // Preserve an ordinary tap before beginning the repeating burst sequence.
            // Keep the next click at least one normal click interval away when start delay is zero.
            clicksInBurst = 0
            let delay = max(self.configuration.startDelayMilliseconds,
                            self.configuration.clickDelayMilliseconds) / 1000
            return [.cancel, .click, .schedule(after: delay)]
        }
        if !wasRunning || previousMode != self.mode || previousConfiguration != self.configuration {
            clicksInBurst = 0
            return [.cancel, .schedule(after: self.configuration.startDelayMilliseconds / 1000)]
        }
        return []
    }

    public mutating func fire() -> [ClickAction] {
        guard isRunning else { return [.cancel] }
        clicksInBurst += 1
        var delay = configuration.clickDelayMilliseconds / 1000
        if clicksInBurst >= configuration.clicksPerBurst {
            clicksInBurst = 0
            delay += configuration.burstPauseMilliseconds / 1000
        }
        return [.click, .schedule(after: delay)]
    }
}
