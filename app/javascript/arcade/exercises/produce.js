import { escape, addSubmit } from "arcade/exercise_helpers"
import { diffWords } from "arcade/diff"

export function render(root, exercise, ctx) {
  root.innerHTML = `<p class="arena-eyebrow">Produce · recall without the model</p><h2>${escape(exercise.prompt)}</h2><p class="arena-question-context">${escape(exercise.context)}</p><p class="arena-instruction">Cue: ${escape(exercise.payload?.cue || "State the decision and the evidence.")}</p><label for="arena-response">Your answer</label><textarea id="arena-response" class="arena-input" rows="6" autocomplete="off"></textarea><label for="arena-self-rating">Self-rate your recall (1–4)</label><select id="arena-self-rating" class="arena-input"><option value="">Choose</option><option value="1">1 · again</option><option value="2">2 · hard</option><option value="3">3 · good</option><option value="4">4 · easy</option></select>`
  root.insertAdjacentHTML("beforeend", `<p class="arena-response-scope">Use your own words. After submitting, compare the meaning, wording, and evidence with the model. The automatic result checks phrase recall; it does not assess your fluency or all valid paraphrases.</p>`)
  watchForReveal(root, ctx)
  addSubmit(root, ctx, "Submit production")
}

export function collect(root) { return { response_text: root.querySelector("#arena-response")?.value || "", self_rating: root.querySelector("#arena-self-rating")?.value || "" } }

function watchForReveal(root, ctx) {
  const feedback = root.closest(".arena-exercise-wrap")?.querySelector(".arena-feedback")
  if (!feedback || typeof MutationObserver === "undefined") return

  const observer = new MutationObserver(() => {
    const answer = feedback.querySelector(".arena-answer-reveal")
    if (!answer || feedback.querySelector("[data-arena-production-diff]")) return

    const label = answer.querySelector("strong")?.textContent || ""
    const model = answer.textContent.replace(label, "").replace(/^\s*:\s*/, "").trim()
    if (!model || model === "Recorded. Keep the distinction explicit.") return

    const learner = root.querySelector("#arena-response")?.value || ""
    const comparison = diffWords(learner, model)
    const section = document.createElement("section")
    section.className = "arena-production-diff"
    section.dataset.arenaProductionDiff = "true"
    section.setAttribute("aria-label", "Reveal-only wording comparison")
    const eyebrow = document.createElement("p")
    eyebrow.className = "arena-eyebrow"
    eyebrow.textContent = "Reveal · wording delta"
    const heading = document.createElement("h3")
    heading.textContent = "Compare your wording"
    const note = document.createElement("p")
    note.className = "arena-muted"
    note.textContent = "Your wording and the model wording are compared after reveal; this is not a pronunciation score."
    section.append(eyebrow, heading, note)
    appendLine(section, "Your wording", comparison.learner)
    appendLine(section, "Model wording", comparison.model)
    answer.after(section)
  })
  observer.observe(feedback, { childList: true, subtree: true })
  ctx.cleanup?.push(() => observer.disconnect())
}

function appendLine(parent, label, segments) {
  const line = document.createElement("p")
  const strong = document.createElement("strong")
  strong.textContent = `${label}: `
  line.append(strong)
  if (segments.length === 0) {
    const empty = document.createElement("span")
    empty.textContent = "(no text)"
    line.append(empty)
    parent.append(line)
    return
  }

  segments.forEach((segment, index) => {
    const element = document.createElement(segment.kind === "removed" ? "del" : segment.kind === "added" ? "ins" : "span")
    element.textContent = `${index === 0 ? "" : " "}${segment.text}`
    line.append(element)
  })
  parent.append(line)
}
