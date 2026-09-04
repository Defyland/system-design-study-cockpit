import { escape, addSubmit, keyboardChoice } from "arcade/exercise_helpers"

export function render(root, exercise, ctx) {
  const blanks = exercise.payload?.blanks || []
  const renderToken = (token) => {
    const match = String(token).match(/^(.*)\[(blank-\d+)\](.*)$/)
    return match ? `${escape(match[1])}<mark data-arena-blank="${escape(match[2])}">_____</mark>${escape(match[3])}` : escape(token)
  }
  root.innerHTML = `<p class="arena-eyebrow">Cloze · rebuild the anchors</p><h2>Complete the answer's precise spans.</h2><p class="arena-cloze-line">${(exercise.payload?.tokens || []).map(renderToken).join(" ")}</p><div class="arena-cloze-blanks"></div>`
  const container = root.querySelector(".arena-cloze-blanks")
  blanks.forEach((blank) => {
    const section = document.createElement("section"); section.className = "arena-cloze-blank"; section.dataset.arenaBlank = blank.id
    const title = document.createElement("p"); title.className = "arena-instruction"; title.textContent = `Blank ${blank.id.replace("blank-", "")}`; section.append(title)
    const bank = document.createElement("div"); bank.className = "arena-chip-bank"; bank.setAttribute("aria-label", `Answer for ${blank.id}`)
    if (blank.input_mode === "typed") {
      const input = document.createElement("input"); input.type = "text"; input.className = "arena-input"; input.dataset.arenaClozeInput = "true"; input.autocomplete = "off"; input.spellcheck = false; input.setAttribute("aria-label", `Type the missing phrase for ${blank.id}`); bank.append(input)
    } else {
      ;(blank.chips || []).forEach((chip) => { const choice = document.createElement("button"); choice.type = "button"; choice.className = "arena-chip"; choice.dataset.arenaChip = chip; choice.setAttribute("aria-pressed", "false"); choice.textContent = chip; choice.addEventListener("click", () => { bank.querySelectorAll(".arena-chip").forEach((other) => { other.classList.remove("is-selected"); other.setAttribute("aria-pressed", "false") }); choice.classList.add("is-selected"); choice.setAttribute("aria-pressed", "true") }); bank.append(choice) })
    }
    section.append(bank); container.append(section)
  })
  ctx.keyboard = (key) => {
    const sections = Array.from(root.querySelectorAll(".arena-cloze-blank"))
    const focused = document.activeElement?.closest(".arena-cloze-blank")
    const section = focused || sections.find((candidate) => !candidate.querySelector(".arena-chip.is-selected")) || sections[0]
    if (!section) return false

    return keyboardChoice(section, key, ".arena-chip")
  }
  addSubmit(root, ctx)
}

export function collect(root) {
  const response = {}
  root.querySelectorAll(".arena-cloze-blank").forEach((blank) => { response[blank.dataset.arenaBlank] = blank.querySelector("[data-arena-cloze-input]")?.value || blank.querySelector(".arena-chip.is-selected")?.dataset.arenaChip || "" })
  return { response }
}
