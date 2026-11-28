import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { createImageSortHook } from "./image_sort.js"

// vi.mock is hoisted to the top of the file by vitest, so this runs before imports.
vi.mock("sortablejs", () => {
  // Track the onEnd callback so tests can trigger it.
  let capturedOnEnd = null

  // Must use `function` (not arrow) so it can be used as a constructor via `new`.
  const MockSortable = vi.fn(function(_el, opts) {
    capturedOnEnd = opts.onEnd || null
    this.destroy = vi.fn()
    // Test-only helper to fire the onEnd callback
    this._triggerOnEnd = () => { if (capturedOnEnd) capturedOnEnd() }
  })

  return { default: MockSortable }
})

function createContainer(refs = ["ref-a", "ref-b"]) {
  const container = document.createElement("div")
  container.id = "upload-entries"
  refs.forEach(ref => {
    const div = document.createElement("div")
    div.id = `upload-entry-${ref}`
    div.dataset.ref = ref
    container.appendChild(div)
  })
  document.body.appendChild(container)
  return container
}

function createMixedContainer(refs = [], imageIds = []) {
  const container = document.createElement("div")
  container.id = "upload-entries-mixed"
  refs.forEach(ref => {
    const div = document.createElement("div")
    div.dataset.ref = ref
    container.appendChild(div)
  })
  imageIds.forEach(id => {
    const div = document.createElement("div")
    div.dataset.imageId = id
    container.appendChild(div)
  })
  document.body.appendChild(container)
  return container
}

describe("ImageSort hook", () => {
  let pushEventMock

  beforeEach(() => {
    pushEventMock = vi.fn()
  })

  afterEach(() => {
    document.body.innerHTML = ""
    vi.clearAllMocks()
  })

  it("initializes Sortable on the container when mounted", async () => {
    const Sortable = (await import("sortablejs")).default
    const el = createContainer()
    const hook = createImageSortHook()
    hook.el = el
    hook.pushEvent = pushEventMock

    hook.mounted()

    expect(Sortable).toHaveBeenCalledWith(el, expect.objectContaining({
      animation: 150,
      ghostClass: "opacity-40"
    }))
  })

  it("pushes reorder_images with ref objects in current DOM order on drag end", async () => {
    const Sortable = (await import("sortablejs")).default
    const el = createContainer(["ref-a", "ref-b"])
    const hook = createImageSortHook()
    hook.el = el
    hook.pushEvent = pushEventMock

    hook.mounted()

    // Simulate drag: move ref-b before ref-a in the DOM
    const [childA, childB] = Array.from(el.children)
    el.insertBefore(childB, childA)

    // Fire the onEnd callback via the test helper on the mock instance
    const sortableInstance = Sortable.mock.instances[0]
    sortableInstance._triggerOnEnd()

    expect(pushEventMock).toHaveBeenCalledWith("reorder_images", {
      order: [{ ref: "ref-b" }, { ref: "ref-a" }]
    })
  })

  it("reflects unchanged ref order when no drag occurred", async () => {
    const Sortable = (await import("sortablejs")).default
    const el = createContainer(["ref-x", "ref-y", "ref-z"])
    const hook = createImageSortHook()
    hook.el = el
    hook.pushEvent = pushEventMock

    hook.mounted()

    // Fire onEnd without changing DOM order
    const sortableInstance = Sortable.mock.instances[0]
    sortableInstance._triggerOnEnd()

    expect(pushEventMock).toHaveBeenCalledWith("reorder_images", {
      order: [{ ref: "ref-x" }, { ref: "ref-y" }, { ref: "ref-z" }]
    })
  })

  it("skips children without a data-ref or data-image-id attribute", async () => {
    const Sortable = (await import("sortablejs")).default
    const el = createContainer([])
    // Add a child without either attribute (e.g., an error message element)
    const orphan = document.createElement("p")
    orphan.textContent = "Error message"
    el.appendChild(orphan)
    // Add a normal ref child
    const child = document.createElement("div")
    child.dataset.ref = "ref-ok"
    el.appendChild(child)

    const hook = createImageSortHook()
    hook.el = el
    hook.pushEvent = pushEventMock

    hook.mounted()

    const sortableInstance = Sortable.mock.instances[0]
    sortableInstance._triggerOnEnd()

    expect(pushEventMock).toHaveBeenCalledWith("reorder_images", {
      order: [{ ref: "ref-ok" }]
    })
  })

  it("pushes image_id objects for existing image cards", async () => {
    const Sortable = (await import("sortablejs")).default
    const el = createMixedContainer([], ["img-1", "img-2"])
    const hook = createImageSortHook()
    hook.el = el
    hook.pushEvent = pushEventMock

    hook.mounted()

    const sortableInstance = Sortable.mock.instances[0]
    sortableInstance._triggerOnEnd()

    expect(pushEventMock).toHaveBeenCalledWith("reorder_images", {
      order: [{ image_id: "img-1" }, { image_id: "img-2" }]
    })
  })

  it("pushes mixed ref and image_id objects for a combined list", async () => {
    const Sortable = (await import("sortablejs")).default
    const el = createMixedContainer(["ref-new"], ["img-old"])
    const hook = createImageSortHook()
    hook.el = el
    hook.pushEvent = pushEventMock

    hook.mounted()

    // Simulate drag: move img-old before ref-new
    const [childRef, childImg] = Array.from(el.children)
    el.insertBefore(childImg, childRef)

    const sortableInstance = Sortable.mock.instances[0]
    sortableInstance._triggerOnEnd()

    expect(pushEventMock).toHaveBeenCalledWith("reorder_images", {
      order: [{ image_id: "img-old" }, { ref: "ref-new" }]
    })
  })

  it("calls sortable.destroy() when hook is destroyed", async () => {
    const Sortable = (await import("sortablejs")).default
    const el = createContainer()
    const hook = createImageSortHook()
    hook.el = el
    hook.pushEvent = pushEventMock

    hook.mounted()
    hook.destroyed()

    const sortableInstance = Sortable.mock.instances[0]
    expect(sortableInstance.destroy).toHaveBeenCalled()
    expect(hook.sortable).toBeNull()
  })

  it("does not throw when destroyed without prior mount", () => {
    const hook = createImageSortHook()
    hook.el = document.createElement("div")
    hook.pushEvent = pushEventMock

    expect(() => hook.destroyed()).not.toThrow()
  })
})

describe("ImageSort hook — move buttons", () => {
  // Cards as the photos component renders them: a pending upload, then saved
  // images, each with Move earlier / Move later buttons. An upload error
  // paragraph sits between cards, as it can on the real page.
  function cards() {
    const container = document.createElement("div")
    container.innerHTML = `
      <div data-ref="up-1">
        <button type="button" data-photo-move="earlier">Move earlier</button>
        <button type="button" data-photo-move="later">Move later</button>
      </div>
      <p class="text-error">up-1: File is too large</p>
      <div data-image-id="img-1">
        <button type="button" data-photo-move="earlier">Move earlier</button>
        <button type="button" data-photo-move="later">Move later</button>
      </div>
      <div data-image-id="img-2">
        <button type="button" data-photo-move="earlier">Move earlier</button>
        <button type="button" data-photo-move="later">Move later</button>
      </div>
    `
    document.body.appendChild(container)
    const hook = createImageSortHook()
    hook.el = container
    hook.pushEvent = vi.fn()
    hook.mounted()
    return { container, hook }
  }

  const order = container =>
    [...container.querySelectorAll("[data-ref], [data-image-id]")].map(
      el => el.dataset.ref || el.dataset.imageId
    )

  const button = (container, id, dir) =>
    container.querySelector(`[data-ref="${id}"], [data-image-id="${id}"]`)
      .querySelector(`[data-photo-move="${dir}"]`)

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("Move later swaps a photo with the next one, skipping non-photo rows", () => {
    const { container, hook } = cards()

    button(container, "up-1", "later").click()

    expect(order(container)).toEqual(["img-1", "up-1", "img-2"])
    expect(hook.pushEvent).toHaveBeenCalledWith("reorder_images", {
      order: [{ image_id: "img-1" }, { ref: "up-1" }, { image_id: "img-2" }]
    })
  })

  it("Move earlier swaps a photo with the previous one", () => {
    const { container, hook } = cards()

    button(container, "img-2", "earlier").click()

    expect(order(container)).toEqual(["up-1", "img-2", "img-1"])
    expect(hook.pushEvent).toHaveBeenCalledWith("reorder_images", {
      order: [{ ref: "up-1" }, { image_id: "img-2" }, { image_id: "img-1" }]
    })
  })

  it("does nothing at the ends of the list", () => {
    const { container, hook } = cards()

    button(container, "up-1", "earlier").click()
    button(container, "img-2", "later").click()

    expect(order(container)).toEqual(["up-1", "img-1", "img-2"])
    expect(hook.pushEvent).not.toHaveBeenCalled()
  })

  it("keeps keyboard focus on the button that was pressed", () => {
    const { container } = cards()
    const later = button(container, "img-1", "later")
    later.focus()

    later.click()

    expect(document.activeElement).toBe(later)
  })
})
