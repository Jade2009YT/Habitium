//
//  RepCounter.swift
//  HabitiumWatch
//
//  Counts repetitions from the wrist's own motion, using CoreMotion —
//  no external barbell sensor needed, any Apple Watch (SE included) has
//  the accelerometer/gyroscope this needs.
//
//  Honest limitation: this is peak-detection over acceleration magnitude,
//  not the velocity-based training a dedicated barbell sensor (PUSH Band,
//  Vitruve, GymAware...) gives you — no bar-speed/power numbers, just a
//  rep count. It works well for most single-plane lifts (curls, presses,
//  rows) where the wrist itself moves with the weight; it works less well
//  for lifts where the wrist barely moves (e.g. squats without holding
//  anything, leg press). Good enough to auto-log "I trained today"
//  without a wearable dedicated to the task — not a lab instrument.
//
//  Algorithm: smooth the raw acceleration magnitude with a simple
//  exponential moving average (kills sensor noise), then count a rep on
//  each rising edge that crosses `threshold`, debounced by `minInterval`
//  so a single rep's up-and-down motion can't be counted twice.
//

import CoreMotion
import Observation

@MainActor
@Observable
final class RepCounter {

    private(set) var repCount = 0
    private(set) var isRunning = false

    /// Tune these if reps are over/under-counted for a given exercise —
    /// exposed as `var` (not `let`) so a future settings screen could
    /// make them adjustable per person/exercise instead of hardcoded.
    var threshold: Double = 0.18
    var minInterval: TimeInterval = 0.5

    private let motionManager = CMMotionManager()
    private var smoothedMagnitude: Double = 0
    private var isAboveThreshold = false
    private var lastRepDate: Date = .distantPast

    private static let smoothingFactor = 0.2 // higher = less smoothing, more responsive

    func start() {
        guard motionManager.isDeviceMotionAvailable, !isRunning else { return }
        reset()
        isRunning = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
    }

    func reset() {
        repCount = 0
        smoothedMagnitude = 0
        isAboveThreshold = false
        lastRepDate = .distantPast
    }

    private func process(_ motion: CMDeviceMotion) {
        let accel = motion.userAcceleration
        let magnitude = (accel.x * accel.x + accel.y * accel.y + accel.z * accel.z).squareRoot()

        smoothedMagnitude += Self.smoothingFactor * (magnitude - smoothedMagnitude)

        let now = Date()
        if smoothedMagnitude > threshold {
            if !isAboveThreshold, now.timeIntervalSince(lastRepDate) > minInterval {
                repCount += 1
                lastRepDate = now
            }
            isAboveThreshold = true
        } else {
            isAboveThreshold = false
        }
    }
}
