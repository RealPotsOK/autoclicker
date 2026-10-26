import Testing
@testable import AutoClickCore

struct ClickStateMachineTests {
    @Test func testLaunchAndReadinessNeverStartClicking() {
        var state = ClickStateMachine()
        #expect(state.update(ready: true) == [.cancel])
        #expect(!state.isRunning)
        #expect(state.fire() == [.cancel])
    }

    @Test func testHoldRequiresPhysicalPressAndReleaseCancelsImmediately() {
        var state = ClickStateMachine()
        _ = state.update(ready: true)
        #expect(state.update(mode: .hold) == [.cancel])
        #expect(state.update(mouseHeld: true) == [.cancel, .click, .schedule(after: 1)])
        #expect(state.fire() == [.click, .schedule(after: 0.1)])
        #expect(state.update(mouseHeld: false) == [.cancel])
        #expect(state.fire() == [.cancel])
        #expect(state.update(mouseHeld: true) == [.cancel, .click, .schedule(after: 1)])
    }

    @Test func testQuickTapClicksImmediatelyWithoutStartingARepeatingBurst() {
        var state = ClickStateMachine()
        _ = state.update(mode: .hold, ready: true)
        #expect(state.update(mouseHeld: true) == [.cancel, .click, .schedule(after: 1)])
        #expect(state.clicksInBurst == 0)
        #expect(state.update(mouseHeld: false) == [.cancel])
        #expect(state.fire() == [.cancel])
    }

    @Test func testImmediateHoldClickPrecedesTheFullBurstSequence() {
        var state = ClickStateMachine(configuration: .init(
            clickDelayMilliseconds: 100, clicksPerBurst: 2,
            burstPauseMilliseconds: 500, startDelayMilliseconds: 250
        ))
        _ = state.update(mode: .hold, ready: true)
        #expect(state.update(mouseHeld: true) == [.cancel, .click, .schedule(after: 0.25)])
        #expect(state.clicksInBurst == 0)
        #expect(state.fire() == [.click, .schedule(after: 0.1)])
        #expect(state.clicksInBurst == 1)
        #expect(state.fire() == [.click, .schedule(after: 0.6)])
    }

    @Test func testZeroStartDelayStillSpacesTheImmediateHoldClick() {
        var state = ClickStateMachine(configuration: .init(clickDelayMilliseconds: 100, startDelayMilliseconds: 0))
        _ = state.update(mode: .hold, ready: true)
        #expect(state.update(mouseHeld: true) == [.cancel, .click, .schedule(after: 0.1)])
    }

    @Test func testResumingOrSwitchingToHoldDoesNotInventAPhysicalPress() {
        var state = ClickStateMachine()
        #expect(state.update(mode: .hold, mouseHeld: true, ready: true) == [.cancel, .schedule(after: 1)])
        _ = state.update(suspended: true)
        #expect(state.update(suspended: false) == [.cancel, .schedule(after: 1)])
        #expect(state.update(configuration: .init(startDelayMilliseconds: 50)) == [.cancel, .schedule(after: 0.05)])
    }

    @Test func testContinuousDoesNotRequireMouseAndSwitchesFromHold() {
        var state = ClickStateMachine()
        _ = state.update(ready: true)
        _ = state.update(mode: .hold)
        #expect(state.update(mode: .continuous) == [.cancel, .schedule(after: 1)])
        #expect(state.isRunning)
        #expect(state.update(mouseHeld: false) == [])
        #expect(state.update(mode: .hold) == [.cancel])
        #expect(!state.isRunning)
    }

    @Test func testSwitchingModeWhileHeldRestartsDelayAndBurst() {
        var state = ClickStateMachine(configuration: .init(clicksPerBurst: 3))
        _ = state.update(mode: .hold, mouseHeld: true, ready: true)
        _ = state.fire()
        #expect(state.clicksInBurst == 1)
        #expect(state.update(mode: .continuous) == [.cancel, .schedule(after: 1)])
        #expect(state.clicksInBurst == 0)
        #expect(state.update(mode: .off) == [.cancel])
        #expect(state.fire() == [.cancel])
    }

    @Test func testBurstPauseIsAddedOnlyAfterEveryCompleteBurst() {
        var state = ClickStateMachine(configuration: .init(
            clickDelayMilliseconds: 100, clicksPerBurst: 3,
            burstPauseMilliseconds: 500, startDelayMilliseconds: 250
        ))
        #expect(state.update(mode: .continuous, ready: true) == [.cancel, .schedule(after: 0.25)])
        for _ in 0..<2 {
            #expect(state.fire() == [.click, .schedule(after: 0.1)])
            #expect(state.fire() == [.click, .schedule(after: 0.1)])
            #expect(state.fire() == [.click, .schedule(after: 0.6)])
        }
    }

    @Test func testOneClickBurstsStillRespectClickDelay() {
        var state = ClickStateMachine(configuration: .init(clickDelayMilliseconds: 20, startDelayMilliseconds: 0))
        #expect(state.update(mode: .continuous, ready: true) == [.cancel, .schedule(after: 0)])
        #expect(state.fire() == [.click, .schedule(after: 0.02)])
    }

    @Test func testSettingsPanelAndPermissionLossCancelEvenContinuousMode() {
        var state = ClickStateMachine()
        _ = state.update(mode: .continuous, ready: true)
        #expect(state.update(suspended: true) == [.cancel])
        #expect(state.fire() == [.cancel])
        #expect(state.update(suspended: false) == [.cancel, .schedule(after: 1)])
        #expect(state.update(ready: false) == [.cancel])
        #expect(state.fire() == [.cancel])
    }

    @Test func testTimingChangesRestartTheCycleWithTheNewDelay() {
        var state = ClickStateMachine()
        _ = state.update(mode: .continuous, ready: true)
        #expect(state.update(configuration: .init(startDelayMilliseconds: 50)) == [.cancel, .schedule(after: 0.05)])
    }

    @Test func testMalformedSettingsCannotCreateAnUnboundedClickLoop() {
        let settings = ClickConfiguration(
            clickDelayMilliseconds: -.infinity, clicksPerBurst: -10,
            burstPauseMilliseconds: .nan, startDelayMilliseconds: -50
        ).validated
        #expect(settings.clickDelayMilliseconds == 100)
        #expect(settings.clicksPerBurst == 1)
        #expect(settings.burstPauseMilliseconds == 0)
        #expect(settings.startDelayMilliseconds == 0)
        #expect(ClickConfiguration(clickDelayMilliseconds: 0).validated.clickDelayMilliseconds == 10)
        #expect(ClickConfiguration(clicksPerBurst: 99999).validated.clicksPerBurst == 1000)
    }
}
