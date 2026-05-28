import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { setupCooperativeTouch } from "./map_touch.js"

function createMapStub() {
  let enabled = true
  const container = document.createElement("div")
  container.id = "map"
  document.body.appendChild(container)

  return {
    container,
    dragging: {
      enable: vi.fn(() => {
        enabled = true
      }),
      disable: vi.fn(() => {
        enabled = false
      }),
      enabled: vi.fn(() => enabled),
    },
    getContainer: vi.fn(() => container),
  }
}

function dispatchTouchEvent(container, type, touchesCount) {
  const event = new Event(type)
  Object.defineProperty(event, "touches", {
    configurable: true,
    value: Array.from({ length: touchesCount }, () => ({})),
  })
  container.dispatchEvent(event)
}

describe("setupCooperativeTouch", () => {
  beforeEach(() => {
    vi.useFakeTimers()
    sessionStorage.clear()

    Object.defineProperty(navigator, "maxTouchPoints", {
      configurable: true,
      value: 1,
    })
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
    document.body.innerHTML = ""
    sessionStorage.clear()
  })

  it("disables dragging initially on touch-capable devices", () => {
    const map = createMapStub()

    setupCooperativeTouch(map)

    expect(map.dragging.disable).toHaveBeenCalled()
  })

  it("shows hint on first single-finger touch and stores session flag", () => {
    const map = createMapStub()
    setupCooperativeTouch(map)

    const hint = map.container.querySelector("div")
    expect(hint.classList.contains("hidden")).toBe(true)

    dispatchTouchEvent(map.container, "touchstart", 1)

    expect(hint.classList.contains("hidden")).toBe(false)
    expect(sessionStorage.getItem("revix:map-two-finger-hint-shown")).toBe("1")

    vi.advanceTimersByTime(1200)
    expect(hint.classList.contains("hidden")).toBe(true)
  })

  it("does not re-show hint after session flag is set", () => {
    const map = createMapStub()
    setupCooperativeTouch(map)
    const hint = map.container.querySelector("div")

    dispatchTouchEvent(map.container, "touchstart", 1)
    vi.advanceTimersByTime(1200)
    expect(hint.classList.contains("hidden")).toBe(true)

    dispatchTouchEvent(map.container, "touchstart", 1)
    expect(hint.classList.contains("hidden")).toBe(true)
  })

  it("enables dragging for two-finger gesture and disables it when touch count drops", () => {
    const map = createMapStub()
    setupCooperativeTouch(map)

    dispatchTouchEvent(map.container, "touchstart", 2)
    expect(map.dragging.enable).toHaveBeenCalled()

    dispatchTouchEvent(map.container, "touchend", 1)
    expect(map.dragging.disable).toHaveBeenCalled()
  })

  it("disables dragging on touchcancel", () => {
    const map = createMapStub()
    setupCooperativeTouch(map)

    dispatchTouchEvent(map.container, "touchstart", 2)
    dispatchTouchEvent(map.container, "touchcancel", 0)

    expect(map.dragging.disable).toHaveBeenCalled()
  })
})
