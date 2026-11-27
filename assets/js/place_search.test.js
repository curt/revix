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

function makeForm({ withLocateBtn = false, autoLocate = false } = {}) {
  const form = document.createElement("form")
  if (autoLocate) {
    form.dataset.autoLocate = "true"
  }
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

describe("PlaceSearch hook — auto-locate (data-auto-locate=\"true\")", () => {
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

  it("requests geolocation on mount", () => {
    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    mountHook(form)

    expect(geolocationMock.getCurrentPosition).toHaveBeenCalledOnce()
  })

  it("does not request geolocation on mount when the attribute is absent", () => {
    const form = makeForm({ withLocateBtn: true })
    mountHook(form)

    expect(geolocationMock.getCurrentPosition).not.toHaveBeenCalled()
  })

  it("does not request geolocation on mount when the attribute is \"false\"", () => {
    const form = makeForm({ withLocateBtn: true })
    form.dataset.autoLocate = "false"
    mountHook(form)

    expect(geolocationMock.getCurrentPosition).not.toHaveBeenCalled()
  })

  it("shows Locating... while the automatic request is pending", () => {
    // getCurrentPosition does not call the callback — simulates pending request
    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    mountHook(form)

    expect(form.querySelector("#locate-status").textContent).toBe("Locating...")
  })

  it("pushes auto_locate with the coordinates but not the locate event", () => {
    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 25.0 } })
    })

    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    const hook = mountHook(form)

    expect(form.querySelector("#locate-status").textContent).toBe("Located (±25m)")
    // The local DB search fires on mount, but not the OpenStreetMap search
    expect(hook.pushEvent).toHaveBeenCalledWith("auto_locate", {
      lat: 40.0, lon: -105.0, accuracy: 25.0
    })
    expect(hook.pushEvent).not.toHaveBeenCalledWith("locate", expect.anything())
  })

  it("keeps the locate button enabled after auto-locate succeeds", () => {
    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 10.0 } })
    })

    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    mountHook(form)

    expect(form.querySelector("#locate-btn").disabled).toBe(false)
  })

  it("clicking the button after auto-locate pushes locate with the cached coordinates", () => {
    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 10.0 } })
    })

    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    const hook = mountHook(form)

    form.querySelector("#locate-btn").click()

    // The cached position is reused — no second geolocation request
    expect(geolocationMock.getCurrentPosition).toHaveBeenCalledOnce()
    expect(hook.pushEvent).toHaveBeenCalledWith("locate", {
      lat: 40.0, lon: -105.0, accuracy: 10.0
    })
  })

  it("disables the button while the cached-position search is in flight", () => {
    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 10.0 } })
    })

    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    const hook = mountHook(form)
    const btn = form.querySelector("#locate-btn")

    btn.click()
    expect(btn.disabled).toBe(true)

    // Re-enabled by updated() on LiveView re-render
    hook.updated()
    expect(btn.disabled).toBe(false)
  })

  it("shows the error on auto-locate failure and falls back to a fresh request on click", () => {
    geolocationMock.getCurrentPosition.mockImplementation((_success, error) => {
      error({ message: "Permission denied" })
    })

    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    const hook = mountHook(form)
    const btn = form.querySelector("#locate-btn")

    expect(form.querySelector("#locate-status").textContent).toBe("Error: Permission denied")
    expect(btn.disabled).toBe(false)

    // Clicking retries geolocation instead of using a cached position
    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 51.5, longitude: -0.12, accuracy: 5.0 } })
    })
    btn.click()

    expect(geolocationMock.getCurrentPosition).toHaveBeenCalledTimes(2)
    expect(hook.pushEvent).toHaveBeenCalledWith("locate", {
      lat: 51.5, lon: -0.12, accuracy: 5.0
    })
  })

  it("clicking the button while auto-locate is still pending runs the normal flow", () => {
    // First (automatic) request never resolves
    geolocationMock.getCurrentPosition.mockImplementationOnce(() => {})

    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    const hook = mountHook(form)

    geolocationMock.getCurrentPosition.mockImplementation((success) => {
      success({ coords: { latitude: 40.0, longitude: -105.0, accuracy: 10.0 } })
    })
    form.querySelector("#locate-btn").click()

    expect(geolocationMock.getCurrentPosition).toHaveBeenCalledTimes(2)
    expect(hook.pushEvent).toHaveBeenCalledWith("locate", {
      lat: 40.0, lon: -105.0, accuracy: 10.0
    })
  })

  it("shows unsupported message when geolocation is unavailable", () => {
    Object.defineProperty(navigator, "geolocation", {
      value: undefined,
      configurable: true
    })

    const form = makeForm({ withLocateBtn: true, autoLocate: true })
    const hook = mountHook(form)

    expect(form.querySelector("#locate-status").textContent).toBe("Geolocation not supported")
    const events = hook.pushEvent.mock.calls.map(([name]) => name)
    expect(events).toEqual(["set_defaults"])
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
