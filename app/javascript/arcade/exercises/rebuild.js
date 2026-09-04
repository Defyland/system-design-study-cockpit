import { escape, addSubmit } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  root.innerHTML = `<p class="arena-eyebrow">Rebuild · order the clauses</p><h2>Put the answer back together.</h2><p class="arena-question-context">${escape(exercise.prompt)}</p><ol class="arena-ordered-list" aria-label="Clause chunks"></ol>`
  const list = root.querySelector(".arena-ordered-list")
  const order = []
  const update = () => list.querySelectorAll(".arena-ordered-item").forEach((node) => { const index = order.indexOf(node.dataset.arenaChunk); node.classList.toggle("is-selected", index >= 0); node.setAttribute("aria-pressed", index >= 0 ? "true" : "false"); node.querySelector(".arena-ordered-number").textContent = index >= 0 ? String(index + 1) : "·" })
  ;(exercise.payload?.chunks || []).forEach((chunk) => { const item = document.createElement("li"); item.className = "arena-ordered-item"; item.tabIndex = 0; item.dataset.arenaChunk = chunk.id; item.innerHTML = `<span class="arena-ordered-number">·</span><span>${escape(chunk.text)}</span>`; item.addEventListener("click", () => { const index = order.indexOf(chunk.id); if (index >= 0) order.splice(index, 1); else order.push(chunk.id); update() }); list.append(item) })
  ctx.keyboard = (key) => { const item = list.querySelectorAll(".arena-ordered-item")[Number(key) - 1]; if (item) item.click() }
  root._arenaRebuildOrder = order
  addSubmit(root, ctx, "Check order")
}

export function collect(root) { return { response: Array.isArray(root._arenaRebuildOrder) ? root._arenaRebuildOrder : [] } }
