/**
 * Tests for textarea_resize.js — preserveTextareaSize dom.onBeforeElUpdated callback
 *
 * Run with: npm test (from assets/ directory)
 */
import { describe, it, expect, afterEach } from "vitest"
import { preserveTextareaSize } from "./textarea_resize.js"

function textarea(styles = {}) {
  const el = document.createElement("textarea")
  Object.assign(el.style, styles)
  document.body.appendChild(el)
  return el
}

describe("preserveTextareaSize", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("copies the user-resized inline height onto the incoming element", () => {
    const fromEl = textarea({ height: "220px" })
    const toEl = textarea()

    preserveTextareaSize(fromEl, toEl)

    expect(toEl.style.height).toBe("220px")
  })

  it("copies the user-resized inline width onto the incoming element", () => {
    const fromEl = textarea({ width: "480px" })
    const toEl = textarea()

    preserveTextareaSize(fromEl, toEl)

    expect(toEl.style.width).toBe("480px")
  })

  it("does not overwrite a height the incoming markup sets itself", () => {
    const fromEl = textarea({ height: "220px" })
    const toEl = textarea({ height: "80px" })

    preserveTextareaSize(fromEl, toEl)

    expect(toEl.style.height).toBe("80px")
  })

  it("is a no-op when the live element has no inline height", () => {
    const fromEl = textarea()
    const toEl = textarea()

    preserveTextareaSize(fromEl, toEl)

    expect(toEl.style.height).toBe("")
    expect(toEl.style.width).toBe("")
  })

  it("ignores non-textarea elements", () => {
    const fromEl = document.createElement("input")
    fromEl.style.height = "220px"
    const toEl = document.createElement("input")
    document.body.append(fromEl, toEl)

    preserveTextareaSize(fromEl, toEl)

    expect(toEl.style.height).toBe("")
  })
})
