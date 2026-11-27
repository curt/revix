import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { installLiveViewHold, preserveHeldState } from "./liveview_hold.js"

// Run readiness re-checks synchronously so tests needn't wait on rAF.
const immediate = cb => cb()

function render(html) {
  document.body.innerHTML = html
}

function lvRoot({ connected = false } = {}) {
  return `<div id="root" data-phx-session="s" class="${connected ? "phx-connected" : ""}">`
}

describe("installLiveViewHold", () => {
  let teardown
  let clicks

  beforeEach(() => {
    clicks = vi.fn()
    document.addEventListener("click", clicks)
  })

  afterEach(() => {
    teardown?.()
    teardown = undefined
    document.removeEventListener("click", clicks)
    document.body.innerHTML = ""
    vi.restoreAllMocks()
  })

  const install = () => {
    teardown = installLiveViewHold(document, { schedule: immediate })
  }
  const root = () => document.getElementById("root")
  const flush = () => new Promise(resolve => setTimeout(resolve, 0))

  it("lets clicks through when the LiveView is connected and idle", () => {
    render(`${lvRoot({ connected: true })}<button id="b" type="button">Go</button></div>`)
    install()
    const btn = document.getElementById("b")

    btn.click()

    expect(clicks).toHaveBeenCalledTimes(1)
    expect(btn.classList.contains("phx-held")).toBe(false)
    expect(btn.hasAttribute("aria-busy")).toBe(false)
  })

  it("holds a click before connection and marks the button busy", () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    install()
    const btn = document.getElementById("b")

    btn.click()

    expect(clicks).not.toHaveBeenCalled()
    expect(btn.classList.contains("phx-held")).toBe(true)
    expect(btn.getAttribute("aria-busy")).toBe("true")
  })

  it("prevents the default action of a held click", () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    install()
    const event = new MouseEvent("click", { bubbles: true, cancelable: true })

    document.getElementById("b").dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
  })

  it("replays a held click exactly once when the LiveView connects", async () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    install()
    const btn = document.getElementById("b")
    btn.click()

    root().classList.add("phx-connected")

    await vi.waitFor(() => expect(clicks).toHaveBeenCalledTimes(1))
    expect(clicks.mock.calls[0][0].target).toBe(btn)
    expect(btn.classList.contains("phx-held")).toBe(false)
    expect(btn.hasAttribute("aria-busy")).toBe(false)

    root().classList.add("other")
    await flush()
    expect(clicks).toHaveBeenCalledTimes(1)
  })

  it("does not replay on unrelated mutations while still disconnected", async () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    install()
    document.getElementById("b").click()

    root().classList.add("phx-loading")
    await flush()

    expect(clicks).not.toHaveBeenCalled()
  })

  it("holds clicks while a LiveView push is pending and replays when it settles", async () => {
    render(`${lvRoot({ connected: true })}
      <div id="hook" data-phx-ref-loading="1"></div>
      <button id="b" type="button">Go</button></div>`)
    install()
    const btn = document.getElementById("b")

    btn.click()
    await flush()
    expect(clicks).not.toHaveBeenCalled()
    expect(btn.classList.contains("phx-held")).toBe(true)

    document.getElementById("hook").removeAttribute("data-phx-ref-loading")

    await vi.waitFor(() => expect(clicks).toHaveBeenCalledTimes(1))
  })

  it("replays when the pending element is removed by a patch", async () => {
    render(`${lvRoot({ connected: true })}
      <div id="hook" data-phx-ref-loading="1"></div>
      <button id="b" type="button">Go</button></div>`)
    install()
    document.getElementById("b").click()
    await flush()

    document.getElementById("hook").remove()

    await vi.waitFor(() => expect(clicks).toHaveBeenCalledTimes(1))
  })

  it("holds clicks on phx-click elements and their descendants", async () => {
    render(`${lvRoot()}<div id="backdrop" phx-click="close"><span id="inner">x</span></div></div>`)
    install()

    document.getElementById("inner").click()
    expect(clicks).not.toHaveBeenCalled()
    expect(document.getElementById("backdrop").classList.contains("phx-held")).toBe(true)

    root().classList.add("phx-connected")
    await vi.waitFor(() => expect(clicks).toHaveBeenCalledTimes(1))
    expect(clicks.mock.calls[0][0].target.id).toBe("backdrop")
  })

  it("holds clicks on submit inputs", () => {
    render(`${lvRoot()}<form><input id="s" type="submit" value="Go" /></form></div>`)
    install()

    document.getElementById("s").click()

    expect(clicks).not.toHaveBeenCalled()
  })

  it("does not hold clicks on text inputs inside a phx-click container", () => {
    render(`${lvRoot()}<div phx-click="x"><input id="t" type="text" /></div></div>`)
    install()

    document.getElementById("t").click()

    expect(clicks).toHaveBeenCalledTimes(1)
  })

  it("does not hold clicks on links or elements outside a LiveView", () => {
    render(`${lvRoot()}<a id="a" href="#x">link</a></div><button id="out" type="button">Out</button>`)
    install()

    document.getElementById("a").click()
    document.getElementById("out").click()

    expect(clicks).toHaveBeenCalledTimes(2)
  })

  it("replays only the latest of several held clicks", async () => {
    render(`${lvRoot()}
      <button id="b1" type="button">One</button>
      <button id="b2" type="button">Two</button></div>`)
    install()
    const b1 = document.getElementById("b1")
    const b2 = document.getElementById("b2")

    b1.click()
    b2.click()
    expect(b1.classList.contains("phx-held")).toBe(false)
    expect(b1.hasAttribute("aria-busy")).toBe(false)
    expect(b2.classList.contains("phx-held")).toBe(true)

    root().classList.add("phx-connected")

    await vi.waitFor(() => expect(clicks).toHaveBeenCalledTimes(1))
    expect(clicks.mock.calls[0][0].target).toBe(b2)
  })

  it("drops a held click whose element was removed before connecting", async () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    install()
    const btn = document.getElementById("b")
    btn.click()

    btn.remove()
    root().classList.add("phx-connected")
    await flush()

    expect(clicks).not.toHaveBeenCalled()
    expect(btn.classList.contains("phx-held")).toBe(false)

    root().classList.add("other")
    await flush()
    expect(clicks).not.toHaveBeenCalled()
  })

  it("drops a held click whose element became disabled", async () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    install()
    const btn = document.getElementById("b")
    btn.click()

    btn.disabled = true
    root().classList.add("phx-connected")
    await flush()

    btn.disabled = false
    root().classList.add("other")
    await flush()
    expect(clicks).not.toHaveBeenCalled()
    expect(btn.classList.contains("phx-held")).toBe(false)
  })

  it("holds an implicit submit and replays it with the original submitter", async () => {
    render(`${lvRoot()}<form id="f">
      <input name="q" />
      <button id="draft" type="submit" name="action" value="draft">Draft</button>
      <button id="pub" type="submit" name="action" value="publish">Publish</button>
    </form></div>`)
    install()
    const form = document.getElementById("f")
    const pub = document.getElementById("pub")
    const submits = vi.fn(e => e.preventDefault())
    form.addEventListener("submit", submits)
    const requestSubmit = vi.spyOn(form, "requestSubmit")

    const event = new SubmitEvent("submit", { bubbles: true, cancelable: true, submitter: pub })
    form.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(submits).not.toHaveBeenCalled()
    expect(pub.classList.contains("phx-held")).toBe(true)

    root().classList.add("phx-connected")

    await vi.waitFor(() => expect(submits).toHaveBeenCalledTimes(1))
    expect(requestSubmit).toHaveBeenCalledWith(pub)
    expect(pub.classList.contains("phx-held")).toBe(false)
  })

  it("marks the form's first submit button when a held submit has no submitter", () => {
    render(`${lvRoot()}<form id="f">
      <button id="plain" type="button">Plain</button>
      <button id="first" type="submit">First</button>
    </form></div>`)
    install()

    const event = new SubmitEvent("submit", { bubbles: true, cancelable: true })
    document.getElementById("f").dispatchEvent(event)

    expect(document.getElementById("first").classList.contains("phx-held")).toBe(true)
    expect(document.getElementById("plain").classList.contains("phx-held")).toBe(false)
  })

  it("marks the form itself when it has no submit button", () => {
    render(`${lvRoot()}<form id="f"><input name="q" /></form></div>`)
    install()

    const event = new SubmitEvent("submit", { bubbles: true, cancelable: true })
    document.getElementById("f").dispatchEvent(event)

    expect(document.getElementById("f").classList.contains("phx-held")).toBe(true)
  })

  it("replays a held submit without a submitter once the submitter is gone", async () => {
    render(`${lvRoot()}<form id="f"><button id="go" type="submit">Go</button></form></div>`)
    install()
    const form = document.getElementById("f")
    const go = document.getElementById("go")
    form.addEventListener("submit", e => e.preventDefault())
    const requestSubmit = vi.spyOn(form, "requestSubmit")

    form.dispatchEvent(new SubmitEvent("submit", { bubbles: true, cancelable: true, submitter: go }))
    go.remove()
    root().classList.add("phx-connected")

    await vi.waitFor(() => expect(requestSubmit).toHaveBeenCalledTimes(1))
    expect(requestSubmit).toHaveBeenCalledWith(undefined)
  })

  it("drops a held submit whose form was removed", async () => {
    render(`${lvRoot()}<form id="f"><button type="submit">Go</button></form></div>`)
    install()
    const form = document.getElementById("f")
    const requestSubmit = vi.spyOn(form, "requestSubmit")
    form.dispatchEvent(new SubmitEvent("submit", { bubbles: true, cancelable: true }))

    form.remove()
    root().classList.add("phx-connected")
    await flush()

    expect(requestSubmit).not.toHaveBeenCalled()
  })

  it("lets submits through when the LiveView is ready", () => {
    render(`${lvRoot({ connected: true })}<form id="f"><button type="submit">Go</button></form></div>`)
    install()
    const event = new SubmitEvent("submit", { bubbles: true, cancelable: true })

    document.getElementById("f").dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
  })

  it("ignores submits of forms outside a LiveView", () => {
    render(`<form id="f"><button type="submit">Go</button></form>`)
    install()
    const event = new SubmitEvent("submit", { bubbles: true, cancelable: true })

    document.getElementById("f").dispatchEvent(event)

    expect(event.defaultPrevented).toBe(false)
  })

  it("defers the readiness re-check through the schedule option", async () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    const scheduled = []
    teardown = installLiveViewHold(document, { schedule: cb => scheduled.push(cb) })
    document.getElementById("b").click()

    root().classList.add("phx-connected")
    await flush()
    expect(clicks).not.toHaveBeenCalled()

    scheduled.forEach(cb => cb())
    expect(clicks).toHaveBeenCalledTimes(1)
  })

  it("defaults the schedule to requestAnimationFrame", async () => {
    const raf = vi.spyOn(window, "requestAnimationFrame").mockImplementation(cb => cb())
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    teardown = installLiveViewHold(document)
    document.getElementById("b").click()

    root().classList.add("phx-connected")

    await vi.waitFor(() => expect(clicks).toHaveBeenCalledTimes(1))
    expect(raf).toHaveBeenCalled()
  })

  it("does not schedule re-checks while nothing is held", async () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    const schedule = vi.fn()
    teardown = installLiveViewHold(document, { schedule })

    root().classList.add("phx-connected")
    await flush()

    expect(schedule).not.toHaveBeenCalled()
  })

  it("ignores clicks dispatched on non-element targets", () => {
    render(`${lvRoot()}</div>`)
    install()

    expect(() => document.dispatchEvent(new MouseEvent("click", { bubbles: true }))).not.toThrow()
    expect(clicks).toHaveBeenCalledTimes(1)
  })

  it("stops holding and observing after teardown", async () => {
    render(`${lvRoot()}<button id="b" type="button">Go</button></div>`)
    install()
    const btn = document.getElementById("b")
    btn.click()
    teardown()
    teardown = undefined
    expect(btn.classList.contains("phx-held")).toBe(false)
    expect(btn.hasAttribute("aria-busy")).toBe(false)

    root().classList.add("phx-connected")
    await flush()
    expect(clicks).not.toHaveBeenCalled()

    root().classList.remove("phx-connected")
    btn.click()
    expect(clicks).toHaveBeenCalledTimes(1)
  })
})

describe("preserveHeldState", () => {
  it("copies the held marker onto the incoming element", () => {
    const fromEl = document.createElement("button")
    fromEl.classList.add("phx-held")
    fromEl.setAttribute("aria-busy", "true")
    const toEl = document.createElement("button")
    toEl.className = "btn"

    preserveHeldState(fromEl, toEl)

    expect(toEl.classList.contains("phx-held")).toBe(true)
    expect(toEl.classList.contains("btn")).toBe(true)
    expect(toEl.getAttribute("aria-busy")).toBe("true")
  })

  it("leaves elements that are not held untouched", () => {
    const fromEl = document.createElement("button")
    const toEl = document.createElement("button")

    preserveHeldState(fromEl, toEl)

    expect(toEl.classList.contains("phx-held")).toBe(false)
    expect(toEl.hasAttribute("aria-busy")).toBe(false)
  })

  it("ignores non-element nodes", () => {
    const fromEl = document.createTextNode("x")
    const toEl = document.createTextNode("y")

    expect(() => preserveHeldState(fromEl, toEl)).not.toThrow()
  })
})
