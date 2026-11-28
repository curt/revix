/**
 * Tests for companion_picker.js — CompanionPicker LiveView hook
 *
 * Run with: npm test (from assets/ directory)
 */
import { describe, it, expect, vi, afterEach } from "vitest"
import { createCompanionPickerHook } from "./companion_picker.js"

function mountHook(resultNames = []) {
  const el = document.createElement("div")
  el.innerHTML = `
    <input type="text" data-companion-search />
    <ul>
      ${resultNames.map(n => `<li><button type="button" data-companion-result>${n}</button></li>`).join("")}
    </ul>
  `
  document.body.appendChild(el)
  const hook = createCompanionPickerHook()
  hook.el = el
  hook.mounted()
  return { el, hook, input: el.querySelector("[data-companion-search]"), results: [...el.querySelectorAll("[data-companion-result]")] }
}

function press(target, key) {
  const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
  target.dispatchEvent(event)
  return event
}

afterEach(() => {
  document.body.innerHTML = ""
})

describe("CompanionPicker hook — Enter in the search box", () => {
  it("picks the first result instead of submitting the form", () => {
    const { input, results } = mountHook(["Alice", "Bob"])
    const firstClick = vi.fn()
    const secondClick = vi.fn()
    results[0].addEventListener("click", firstClick)
    results[1].addEventListener("click", secondClick)

    const event = press(input, "Enter")

    expect(event.defaultPrevented).toBe(true)
    expect(firstClick).toHaveBeenCalledTimes(1)
    expect(secondClick).not.toHaveBeenCalled()
  })

  it("clears the search box after picking, since LiveView won't update a focused input", () => {
    const { input } = mountHook(["Alice"])
    input.value = "Ali"

    press(input, "Enter")

    expect(input.value).toBe("")
  })

  it("keeps the typed text when Enter finds no result", () => {
    const { input } = mountHook([])
    const errors = []
    const onError = e => errors.push(e.error)
    window.addEventListener("error", onError)
    input.value = "Zed"

    press(input, "Enter")
    window.removeEventListener("error", onError)

    expect(input.value).toBe("Zed")
    expect(errors).toEqual([])
  })

  it("does not submit the form when there are no results", () => {
    const { input } = mountHook([])
    expect(press(input, "Enter").defaultPrevented).toBe(true)
  })

  it("leaves other keys alone", () => {
    const { input } = mountHook(["Alice"])
    expect(press(input, "a").defaultPrevented).toBe(false)
  })

  it("leaves Enter on other fields alone", () => {
    const { el } = mountHook(["Alice"])
    const other = document.createElement("input")
    el.appendChild(other)
    expect(press(other, "Enter").defaultPrevented).toBe(false)
  })
})

describe("CompanionPicker hook — arrow keys", () => {
  it("ArrowDown in the search box moves focus to the first result", () => {
    const { input, results } = mountHook(["Alice", "Bob"])
    input.focus()

    const event = press(input, "ArrowDown")

    expect(event.defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(results[0])
  })

  it("ArrowDown in the search box does nothing without results", () => {
    const { input } = mountHook([])
    input.focus()

    expect(press(input, "ArrowDown").defaultPrevented).toBe(false)
    expect(document.activeElement).toBe(input)
  })

  it("ArrowDown and ArrowUp move between results", () => {
    const { results } = mountHook(["Alice", "Bob", "Carol"])
    results[0].focus()

    expect(press(results[0], "ArrowDown").defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(results[1])

    press(results[1], "ArrowDown")
    expect(document.activeElement).toBe(results[2])

    press(results[2], "ArrowUp")
    expect(document.activeElement).toBe(results[1])
  })

  it("ArrowDown on the last result stays there", () => {
    const { results } = mountHook(["Alice", "Bob"])
    results[1].focus()

    press(results[1], "ArrowDown")
    expect(document.activeElement).toBe(results[1])
  })

  it("ArrowUp on the first result returns to the search box", () => {
    const { input, results } = mountHook(["Alice", "Bob"])
    results[0].focus()

    expect(press(results[0], "ArrowUp").defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(input)
  })

  it("Escape on a result returns to the search box", () => {
    const { input, results } = mountHook(["Alice", "Bob"])
    results[1].focus()

    press(results[1], "Escape")
    expect(document.activeElement).toBe(input)
  })

  it("Enter on a focused result is left to the button", () => {
    const { results } = mountHook(["Alice"])
    expect(press(results[0], "Enter").defaultPrevented).toBe(false)
  })
})
