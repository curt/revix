import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { MAX_LOCKED_MIN_ZOOM, fitBoundsAndLockZoom, setupResizeRelock } from "./map_zoom.js"

function createMapStub(zoom, boundsZoom = zoom) {
  let currentZoom = zoom
  return {
    fitBounds: vi.fn(),
    setMinZoom: vi.fn(),
    getZoom: vi.fn(() => currentZoom),
    getBoundsZoom: vi.fn(() => boundsZoom),
    setZoom(z) {
      currentZoom = z
    },
  }
}

describe("fitBoundsAndLockZoom", () => {
  it("fits bounds then locks min zoom to the resulting zoom level", () => {
    const map = createMapStub(5)
    const bounds = { south: 1 }
    const options = { padding: [50, 50] }

    fitBoundsAndLockZoom(map, bounds, options)

    expect(map.fitBounds).toHaveBeenCalledWith(bounds, options)
    expect(map.setMinZoom).toHaveBeenCalledWith(5)
  })

  it("caps the locked min zoom at MAX_LOCKED_MIN_ZOOM for tight-fit bounds (e.g. a single pin)", () => {
    const map = createMapStub(MAX_LOCKED_MIN_ZOOM + 6)
    const bounds = { south: 1 }
    const options = { padding: [50, 50] }

    fitBoundsAndLockZoom(map, bounds, options)

    expect(map.setMinZoom).toHaveBeenCalledWith(MAX_LOCKED_MIN_ZOOM)
  })

  it("does not clamp when the fitted zoom is already below the cap", () => {
    const map = createMapStub(MAX_LOCKED_MIN_ZOOM - 3)

    fitBoundsAndLockZoom(map, {}, {})

    expect(map.setMinZoom).toHaveBeenCalledWith(MAX_LOCKED_MIN_ZOOM - 3)
  })
})

describe("setupResizeRelock", () => {
  beforeEach(() => {
    vi.spyOn(window, "addEventListener")
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("registers a resize listener", () => {
    const map = createMapStub(5)
    setupResizeRelock(map, () => ({}), {})

    expect(window.addEventListener).toHaveBeenCalledWith("resize", expect.any(Function))
  })

  it("recomputes the min-zoom floor from fresh bounds without moving the current view", () => {
    const map = createMapStub(9, 6)
    const boundsA = { label: "a" }
    const boundsB = { label: "b" }
    let bounds = boundsA
    const options = { padding: [50, 50] }

    const relock = setupResizeRelock(map, () => bounds, options)

    bounds = boundsB
    relock()

    expect(map.getBoundsZoom).toHaveBeenCalledWith(boundsB, false, [100, 100])
    expect(map.setMinZoom).toHaveBeenCalledWith(6)
    expect(map.fitBounds).not.toHaveBeenCalled()
  })

  it("preserves a user's zoomed-out view when the recomputed floor is still below it", () => {
    const map = createMapStub(3, 6)
    const relock = setupResizeRelock(map, () => ({}), { padding: [50, 50] })

    relock()

    expect(map.setMinZoom).toHaveBeenCalledWith(6)
    expect(map.getZoom()).toBe(3)
  })

  it("caps the recomputed min-zoom floor at MAX_LOCKED_MIN_ZOOM on relock", () => {
    const map = createMapStub(MAX_LOCKED_MIN_ZOOM + 4, MAX_LOCKED_MIN_ZOOM + 4)
    const relock = setupResizeRelock(map, () => ({}), {})

    relock()

    expect(map.setMinZoom).toHaveBeenCalledWith(MAX_LOCKED_MIN_ZOOM)
  })

  it("invokes the relock handler when a resize event fires", () => {
    const map = createMapStub(5)
    const bounds = {}
    setupResizeRelock(map, () => bounds, {})

    window.dispatchEvent(new Event("resize"))

    expect(map.getBoundsZoom).toHaveBeenCalledWith(bounds, false, [0, 0])
  })
})
