const MAX_TOKENS = 256

// A small word-level diff for the reveal-only production comparison. The
// learner and model strings are kept separate so the caller can render them
// with native <del>/<ins> semantics without putting the model in the lesson
// payload before a result has been recorded.
export function diffWords(learner, model) {
  const left = tokens(learner)
  const right = tokens(model)
  const lengths = Array.from({ length: left.length + 1 }, () => Array(right.length + 1).fill(0))

  for (let leftIndex = left.length - 1; leftIndex >= 0; leftIndex -= 1) {
    for (let rightIndex = right.length - 1; rightIndex >= 0; rightIndex -= 1) {
      lengths[leftIndex][rightIndex] = left[leftIndex] === right[rightIndex]
        ? lengths[leftIndex + 1][rightIndex + 1] + 1
        : Math.max(lengths[leftIndex + 1][rightIndex], lengths[leftIndex][rightIndex + 1])
    }
  }

  const learnerSegments = []
  const modelSegments = []
  let leftIndex = 0
  let rightIndex = 0
  while (leftIndex < left.length || rightIndex < right.length) {
    if (leftIndex < left.length && rightIndex < right.length && left[leftIndex] === right[rightIndex]) {
      append(learnerSegments, "same", left[leftIndex])
      append(modelSegments, "same", right[rightIndex])
      leftIndex += 1
      rightIndex += 1
    } else if (rightIndex >= right.length || (leftIndex < left.length && lengths[leftIndex + 1][rightIndex] >= lengths[leftIndex][rightIndex + 1])) {
      append(learnerSegments, "removed", left[leftIndex])
      leftIndex += 1
    } else {
      append(modelSegments, "added", right[rightIndex])
      rightIndex += 1
    }
  }

  return { learner: learnerSegments, model: modelSegments }
}

function tokens(value) {
  return String(value ?? "").trim().split(/\s+/).filter(Boolean).slice(0, MAX_TOKENS)
}

function append(segments, kind, value) {
  const previous = segments[segments.length - 1]
  if (previous?.kind === kind) previous.text = `${previous.text} ${value}`
  else segments.push({ kind, text: value })
}
