const STORAGE_KEY = "arcade:muted"

// Small UI tones. Audio is off until a learner enables it and never requests a
// media device or leaves the browser.
export class ArenaAudio {
  constructor() {
    this.enabled = this.readEnabled()
    this.context = null
  }

  toggle() {
    this.enabled = !this.enabled
    try { window.localStorage.setItem(STORAGE_KEY, String(!this.enabled)) } catch (_error) { /* best effort */ }
    return this.enabled
  }

  play(kind = "tap") {
    if (!this.enabled || !window.AudioContext && !window.webkitAudioContext) return
    try {
      this.context ||= new (window.AudioContext || window.webkitAudioContext)()
      const now = this.context.currentTime
      const oscillator = this.context.createOscillator()
      const gain = this.context.createGain()
      const tones = { tap: 440, listen: 523.25, start: 392, stop: 330, success: 659.25 }
      oscillator.frequency.value = tones[kind] || tones.tap
      oscillator.type = "sine"
      gain.gain.setValueAtTime(0.0001, now)
      gain.gain.exponentialRampToValueAtTime(0.045, now + 0.01)
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.12)
      oscillator.connect(gain).connect(this.context.destination)
      oscillator.start(now)
      oscillator.stop(now + 0.13)
    } catch (_error) { /* Sound is never required for a lesson. */ }
  }

  readEnabled() {
    try { return window.localStorage.getItem(STORAGE_KEY) === "false" } catch (_error) { return false }
  }
}
