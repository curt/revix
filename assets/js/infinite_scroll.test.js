/**
 * Tests for infinite_scroll.js — InfiniteScroll LiveView hook
 *
 * Run with: npm test (from assets/ directory)
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { createInfiniteScrollHook } from "./infinite_scroll.js"

// jsdom does not implement IntersectionObserver, so stub a minimal
// controllable version: capture the callback and expose a way to fire it.
let observedElements
let lastCallback

class FakeIntersectionObserver {
  constructor(callback) {
    lastCallback = callback
    this.observed = []
  }
  observe(el) {
    this.observed.push(el)
    observedElements.push(el)
  }
  disconnect() {
    this.disconnected = true
  }
}

function mountHook(el, { autoReply = false } = {}) {
  const hook = createInfiniteScrollHook()
  hook.el = el
  hook.pushEvent = vi.fn((event, payload, callback) => {
    if (autoReply) callback?.()
  })
  hook.mounted()
  return hook
}

describe("InfiniteScroll hook", () => {
  beforeEach(() => {
    observedElements = []
    vi.stubGlobal("IntersectionObserver", FakeIntersectionObserver)
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    document.body.innerHTML = ""
  })

  it("observes its element on mount", () => {
    const el = document.createElement("div")
    document.body.appendChild(el)
    mountHook(el)

    expect(observedElements).toContain(el)
  })

  it("pushes load_more when the sentinel intersects", () => {
    const el = document.createElement("div")
    document.body.appendChild(el)
    const hook = mountHook(el)

    lastCallback([{ isIntersecting: true }])

    expect(hook.pushEvent).toHaveBeenCalledOnce()
    expect(hook.pushEvent.mock.calls[0][0]).toBe("load_more")
    expect(hook.pushEvent.mock.calls[0][1]).toEqual({})
  })

  it("does not push load_more when not intersecting", () => {
    const el = document.createElement("div")
    document.body.appendChild(el)
    const hook = mountHook(el)

    lastCallback([{ isIntersecting: false }])

    expect(hook.pushEvent).not.toHaveBeenCalled()
  })

  it("allows load_more again after the server replies to the previous push", () => {
    const el = document.createElement("div")
    document.body.appendChild(el)
    const hook = mountHook(el, { autoReply: true })

    lastCallback([{ isIntersecting: true }])
    lastCallback([{ isIntersecting: true }])

    expect(hook.pushEvent).toHaveBeenCalledTimes(2)
  })

  it("does not allow load_more again before the server has replied", () => {
    const el = document.createElement("div")
    document.body.appendChild(el)
    const hook = mountHook(el, { autoReply: false })

    lastCallback([{ isIntersecting: true }])
    lastCallback([{ isIntersecting: true }])

    expect(hook.pushEvent).toHaveBeenCalledTimes(1)
  })

  it("disconnects the observer on destroyed()", () => {
    const el = document.createElement("div")
    document.body.appendChild(el)
    const hook = mountHook(el)

    hook.destroyed()

    expect(hook.observer.disconnected).toBe(true)
  })
})
