export function text(value) {
  return String(value ?? "")
}

export function escape(value) {
  return text(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[character])
}

export function button(label, className = "arena-button") {
  const element = document.createElement("button")
  element.type = "button"
  element.className = className
  element.textContent = label
  return element
}

export function learningMarkup(learning = {}) {
  const structure = Array.isArray(learning.answer_structure) ? learning.answer_structure : []
  const phrases = Array.isArray(learning.useful_phrases) ? learning.useful_phrases : []
  const columns = []
  if (structure.length) columns.push(`<section><h3>Build the answer</h3><ol>${structure.map((step) => `<li>${escape(step)}</li>`).join("")}</ol></section>`)
  if (phrases.length) columns.push(`<section><h3>Useful English</h3><ul>${phrases.map((phrase) => `<li>${escape(phrase)}</li>`).join("")}</ul></section>`)
  const help = learning.pt_help ? `<details class="arena-pt-help"><summary>Ajuda em português</summary><p lang="pt-BR">${escape(learning.pt_help)}</p></details>` : ""
  const versions = learning.answer_versions || {}
  const short = versions.short ? `<details class="arena-pt-help"><summary>Short recruiter answer</summary><p>${escape(versions.short)}</p></details>` : ""
  const deep = versions.deep ? `<details class="arena-pt-help"><summary>Engineering deep dive</summary><p>${escape(versions.deep)}</p></details>` : ""
  const questions = Array.isArray(learning.reasoning_questions) ? learning.reasoning_questions : []
  const reasoning = questions.length ? `<section class="arena-reasoning" aria-label="How I think through this"><h3>How I think through this</h3>${questions.map(({ question, answer }) => `<details class="arena-pt-help"><summary>${escape(question)}</summary><p>${escape(answer)}</p></details>`).join("")}</section>` : ""
  return columns.length || help || short || deep || reasoning ? `<aside class="arena-learning-card" aria-label="English coaching">${reasoning}<div class="arena-learning-grid">${columns.join("")}</div>${short}${deep}${help}</aside>` : ""
}

export function selectedButton(root) {
  return root.querySelector("[data-arena-selected='true']")
}

export function addSubmit(root, ctx, label = "Confirm") {
  const actions = document.createElement("div")
  actions.className = "arena-exercise-actions"
  const submit = button(label)
  submit.dataset.arenaSubmit = "true"
  submit.addEventListener("click", () => ctx.submit())
  const status = document.createElement("span")
  status.className = "arena-submit-status"
  status.dataset.arenaSubmitStatus = "true"
  status.setAttribute("role", "status")
  actions.append(submit, status)
  root.append(actions)
}

export function keyboardChoice(root, key, selector = "[data-arena-choice]") {
  const choice = Array.from(root.querySelectorAll(selector))[Number(key) - 1]
  if (!choice) return false
  choice.click()
  return true
}
