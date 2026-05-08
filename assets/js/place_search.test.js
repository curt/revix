/**
 * Tests for place_search.js — PlaceSearch LiveView hook
 *
 * Run with: npm test (from assets/ directory)
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { createPlaceSearchHook } from "./place_search.js"

// Build a minimal hook instance with a controllable DOM element and a
// pushEvent spy, then call mounted() / updated() directly.
function mountHook(el) {
  const hook = createPlaceSearchHook()
  hook.el = el
  hook.pushEvent = vi.fn()
  hook.mounted()
  return hook
}

function makeForm({ withLocateBtn = false } = {}) {
  const form = document.createElement("form")
  if (withLocateBtn) {
    form.innerHTML = `
      <button type="button" id="locate-btn">Locate me</button>
      <span id="locate-status"></span>
    `
  }
  document.body.appendChild(form)
  return form
}

describe("PlaceSearch hook — set_defaults", () => {
  beforeEach(() => {
    // Fix the timezone so assertions are deterministic.
    // spy on the prototype method rather than replacing the constructor.
    vi.spyOn(Intl, "DateTimeFormat").mockImplementation(() => ({
      resolvedOptions: () => ({ timeZone: "America/Denver" })
    }))
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.useRealTimers()
    document.body.innerHTML = ""
  })

  it("pushes set_defaults on mount even without a locate button", () => {
    const form = makeForm({ withLocateBtn: false })
    const hook = mountHook(form)

    expect(hook.pushEvent).toHaveBeenCalledOnce()
    expect(hook.pushEvent).toHaveBeenCalledWith("set_defaults", expect.objectContaining({
      timezone: "America/Denver"
    }))
  })

  it("pushes set_defaults on mount when locate button is present", () => {
    const form = makeForm({ withLocateBtn: true })
    const hook = mountHook(form)

    expect(hook.pushEvent).toHaveBeenCalledWith("set_defaults", expect.objectContaining({
      timezone: "America/Denver"
    }))
  })

  it("local_datetime has the format YYYY-MM-DDTHH:MM", () => {
    const form = makeForm()
    const hook = mountHook(form)

    const { local_datetime } = hook.pushEvent.mock.calls[0][1]
    expect(local_datetime).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/)
  })

  it("local_datetime reflects a known fixed time", () => {
    // Use a local-time string (no Z) so the expected value is the same
    // regardless of the test runner's timezone offset.
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 4, 8, 14, 5, 0)) // month is 0-indexed

    const form = makeForm()
    const hook = mountHook(form)

    const { local_datetime } = hook.pushEvent.mock.calls[0][1]
    expect(local_datetime).toBe("2026-05-08T14:05")

    vi.useRealTimers()
  })
})

describe("PlaceSearch hook — locate button (geolocation available)", () => {
  let geolocationMock

  beforeEach(() => {
    geolocationMock = {
      getCurrentPosition: vi.fn()
    }
    Object.defineProperty(navigator, "geolocation", {
      value: geolocationMock,
      configurable: true
    })
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("does not register a click handler when locate button is absent", () => {
    const form = makeForm({ withLocateBtn: false })
    mountHook(form)
    // No error thrown, geolocation never called
    expect(geolocationMock.getCurrentPosition).not.toHaveBeenCalled()
  })

  it("clicking locate button calls getCurrentPosition", async () => {
    const form = makeForm({ withLocateBtn: true })
    mountHook(form)

    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 10.0 } })
    })

    form.querySelector("#locate-btn").click()

    expect(geolocationMock.getCurrentPosition).toHaveBeenCalledOnce()
  })

  it("successful geolocation pushes locate event with coordinates", () => {
    const form = makeForm({ withLocateBtn: true })
    const hook = mountHook(form)

    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 10.0 } })
    })

    form.querySelector("#locate-btn").click()

    expect(hook.pushEvent).toHaveBeenCalledWith("locate", {
      lat: 40.0, lon: -105.0, accuracy: 10.0
    })
  })

  it("successful geolocation updates status text", () => {
    const form = makeForm({ withLocateBtn: true })
    mountHook(form)

    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 25.0 } })
    })

    form.querySelector("#locate-btn").click()

    expect(form.querySelector("#locate-status").textContent).toBe("Located (±25m)")
  })

  it("disables locate button during request and leaves it disabled after locate event", () => {
    const form = makeForm({ withLocateBtn: true })
    mountHook(form)
    const btn = form.querySelector("#locate-btn")

    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      expect(btn.disabled).toBe(true)
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 10.0 } })
    })

    btn.click()
    // Button stays disabled after success (re-enabled by updated() on LiveView re-render)
    expect(btn.disabled).toBe(true)
  })

  it("geolocation error updates status and re-enables button", () => {
    const form = makeForm({ withLocateBtn: true })
    mountHook(form)
    const btn = form.querySelector("#locate-btn")

    geolocationMock.getCurrentPosition.mockImplementation((_success, error) => {
      error({ message: "Permission denied" })
    })

    btn.click()

    expect(form.querySelector("#locate-status").textContent).toBe("Error: Permission denied")
    expect(btn.disabled).toBe(false)
  })

  it("sets status to Locating... before position resolves", () => {
    const form = makeForm({ withLocateBtn: true })
    mountHook(form)

    // getCurrentPosition does not call the callback — simulates pending request
    geolocationMock.getCurrentPosition.mockImplementation(() => {})

    form.querySelector("#locate-btn").click()

    expect(form.querySelector("#locate-status").textContent).toBe("Locating...")
  })
})

describe("PlaceSearch hook — locate button (no geolocation API)", () => {
  beforeEach(() => {
    Object.defineProperty(navigator, "geolocation", {
      value: undefined,
      configurable: true
    })
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("clicking locate button shows unsupported message", () => {
    const form = makeForm({ withLocateBtn: true })
    mountHook(form)

    form.querySelector("#locate-btn").click()

    expect(form.querySelector("#locate-status").textContent).toBe("Geolocation not supported")
  })
})

describe("PlaceSearch hook — updated()", () => {
  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("re-enables a disabled locate button on updated", () => {
    const form = makeForm({ withLocateBtn: true })
    const hook = mountHook(form)
    const btn = form.querySelector("#locate-btn")

    btn.disabled = true
    hook.updated()

    expect(btn.disabled).toBe(false)
  })

  it("does nothing on updated when locate button is absent", () => {
    const form = makeForm({ withLocateBtn: false })
    const hook = mountHook(form)
    // Should not throw
    expect(() => hook.updated()).not.toThrow()
  })
})
