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

export function selectedButton(root) {
  return root.querySelector("[data-arena-selected='true']")
}

export function addSubmit(root, ctx, label = "Confirm") {
  const actions = document.createElement("div")
  actions.className = "arena-exercise-actions"
  const submit = button(label)
  submit.dataset.arenaSubmit = "true"
  submit.addEventListener("click", () => ctx.submit())
  actions.append(submit)
  root.append(actions)
}

export function keyboardChoice(root, key, selector = "[data-arena-choice]") {
  const choice = Array.from(root.querySelectorAll(selector))[Number(key) - 1]
  if (!choice) return false
  choice.click()
  return true
}
