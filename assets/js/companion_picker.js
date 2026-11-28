/**
 * CompanionPicker LiveView hook — keyboard support for the companion search.
 *
 * The search box sits inside the checkin or post form, so a bare Enter would
 * submit that form with its first button (Save as Draft). Enter in the box
 * instead picks the first result by clicking its button, and never submits.
 *
 * ArrowDown moves from the box into the results; ArrowDown/ArrowUp move
 * between them; ArrowUp on the first result or Escape returns to the box.
 * Enter or Space on a focused result is the button's own click.
 *
 * Listens on the hook element, so results LiveView re-renders keep working.
 */
export function createCompanionPickerHook() {
  return {
    mounted() {
      this.el.addEventListener("keydown", e => {
        const results = [...this.el.querySelectorAll("[data-companion-result]")]

        if (e.target.matches("[data-companion-search]")) {
          onSearchKey(e, results)
        } else if (e.target.matches("[data-companion-result]")) {
          onResultKey(e, results, this.el.querySelector("[data-companion-search]"))
        }
      })
    }
  }
}

function onSearchKey(e, results) {
  if (e.key === "Enter") {
    e.preventDefault()
    pick(results[0], e.target)
  } else if (e.key === "ArrowDown" && results.length > 0) {
    e.preventDefault()
    results[0].focus()
  }
}

// LiveView doesn't overwrite a focused input, so the box would keep the typed
// text after the server clears the query.
function pick(result, search) {
  if (!result) return
  result.click()
  search.value = ""
}

function onResultKey(e, results, search) {
  const index = results.indexOf(e.target)

  if (e.key === "ArrowDown") {
    e.preventDefault()
    results[index + 1]?.focus()
  } else if (e.key === "ArrowUp") {
    e.preventDefault()
    ;(index === 0 ? search : results[index - 1]).focus()
  } else if (e.key === "Escape") {
    e.preventDefault()
    search.focus()
  }
}
