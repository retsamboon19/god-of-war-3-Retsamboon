// SPDX-License-Identifier: GPL-3.0-or-later
// Controllers iOS sees (GameController framework) as the game's pad, for those SDL does not open:
// some phone controllers (e.g. GameSir's USB-C ones) work in other iOS games but never reach SDL's
// gamepad list, so the game got no input while the on-screen controls hid for them. The runtime
// uses this only while SDL has no gamepad (runtime_pad.c, gow3_gc_pad), so pads SDL already
// handles (DualSense, Xbox) are not read twice.
import Foundation
import GameController

@_silgen_name("gow3_gc_pad")
private func gow3_gc_pad(_ connected: Int32, _ buttons: UInt32, _ sticks: UInt32, _ triggers: UInt32)

final class Gow3GameControllerPad {
  static let shared = Gow3GameControllerPad()

  private var started = false
  private var active: GCController?

  /// Starts following controllers; call on the main thread before the game starts. Idempotent.
  func start() {
    guard !started else { return }
    started = true
    let center = NotificationCenter.default
    center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.choose() }
    center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.choose() }
    center.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] _ in self?.choose() }
    choose()
  }

  /// Follows the current controller, or the first one with a full gamepad profile.
  private func choose() {
    let candidates = GCController.controllers().filter { $0.extendedGamepad != nil }
    let next = candidates.first(where: { $0 === GCController.current }) ?? candidates.first
    if next === active { return }
    active?.extendedGamepad?.valueChangedHandler = nil
    active = next
    guard let pad = next?.extendedGamepad else {
      gow3_gc_pad(0, 0, 0x8080_8080, 0)
      return
    }
    pad.valueChangedHandler = { [weak self] gamepad, _ in self?.publish(gamepad) }
    publish(pad)
  }

  private func publish(_ g: GCExtendedGamepad) {
    var bits: UInt32 = 0
    func on(_ input: GCControllerButtonInput?, _ bit: UInt32) { if input?.isPressed == true { bits |= bit } }
    on(g.buttonA, 0x4000)               // cross
    on(g.buttonB, 0x2000)               // circle
    on(g.buttonX, 0x8000)               // square
    on(g.buttonY, 0x1000)               // triangle
    on(g.leftShoulder, 0x400)           // L1
    on(g.rightShoulder, 0x800)          // R1
    on(g.leftThumbstickButton, 0x2)     // L3
    on(g.rightThumbstickButton, 0x4)    // R3
    on(g.buttonMenu, 0x8)               // Options
    on(g.buttonOptions, 0x8000_0000)    // View/Select: the touchpad's right side, as with SDL's Back
    on(g.dpad.up, 0x10)
    on(g.dpad.right, 0x20)
    on(g.dpad.down, 0x40)
    on(g.dpad.left, 0x80)
    let l2 = Self.trigger(g.leftTrigger.value), r2 = Self.trigger(g.rightTrigger.value)
    if l2 > 30 { bits |= 0x100 }
    if r2 > 30 { bits |= 0x200 }
    // PS4 sticks: 0 is left/up, 255 right/down; GameController's y is up-positive.
    let lx = Self.axis(g.leftThumbstick.xAxis.value), ly = Self.axis(-g.leftThumbstick.yAxis.value)
    let rx = Self.axis(g.rightThumbstick.xAxis.value), ry = Self.axis(-g.rightThumbstick.yAxis.value)
    let sticks = lx | ly << 8 | rx << 16 | ry << 24
    gow3_gc_pad(1, bits, sticks, l2 | r2 << 8)
  }

  private static func axis(_ v: Float) -> UInt32 {
    UInt32(max(0, min(255, ((v + 1) * 127.5).rounded())))
  }

  private static func trigger(_ v: Float) -> UInt32 {
    UInt32(max(0, min(255, (v * 255).rounded())))
  }
}
