// Tiny, dependency-free lesson state machine. The controller owns network IO;
// this object only makes the visible transitions explicit and easy to test.
export const STATES = Object.freeze({
  IDLE: "idle", EXERCISE: "exercise", GRADING: "grading", FEEDBACK: "feedback", BOSS: "boss", RESULTS: "results"
})

export class LessonMachine {
  constructor(total = 0) {
    this.total = total
    this.position = 0
    this.state = STATES.IDLE
  }

  start(position = 0) {
    this.position = Math.max(0, Number(position) || 0)
    this.state = this.position >= this.total ? STATES.RESULTS : STATES.EXERCISE
    return this.snapshot()
  }

  beginGrade() { if (this.state === STATES.EXERCISE) this.state = STATES.GRADING; return this.snapshot() }

  showFeedback() { if (this.state === STATES.GRADING) this.state = STATES.FEEDBACK; return this.snapshot() }

  next() {
    if (this.state === STATES.FEEDBACK) {
      this.position += 1
      this.state = this.position >= this.total ? STATES.RESULTS : STATES.EXERCISE
    }
    return this.snapshot()
  }

  enterBoss() { this.state = STATES.BOSS; return this.snapshot() }
  results() { this.state = STATES.RESULTS; return this.snapshot() }
  snapshot() { return { state: this.state, position: this.position, total: this.total } }
}

export default LessonMachine
