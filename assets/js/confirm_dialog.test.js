/**
 * Tests for confirm_dialog.js — ConfirmDialog LiveView hook
 *
 * Run with: npm test (from assets/ directory)
 */
import { describe, it, expect, vi, afterEach } from "vitest"
import { createConfirmDialogHook } from "./confirm_dialog.js"

// jsdom has no HTMLDialogElement.showModal, so each dialog gets a stub.
function setup() {
  const trigger = document.createElement("button")
  trigger.textContent = "Delete"
  document.body.appendChild(trigger)
  trigger.focus()

  const el = document.createElement("dialog")
  el.innerHTML = `
    <div class="modal-action">
      <button type="button" data-confirm-dialog-cancel>Cancel</button>
      <button type="button">Delete</button>
    </div>
  `
  el.showModal = vi.fn(() => el.setAttribute("open", ""))
  document.body.appendChild(el)

  const hook = createConfirmDialogHook()
  hook.el = el
  hook.mounted()
  return { hook, el, trigger, cancel: el.querySelector("[data-confirm-dialog-cancel]") }
}

afterEach(() => {
  document.body.innerHTML = ""
})

describe("ConfirmDialog hook", () => {
  it("opens the dialog as a modal", () => {
    const { el } = setup()
    expect(el.showModal).toHaveBeenCalledTimes(1)
  })

  it("focuses Cancel so the safe choice is the default", () => {
    const { cancel } = setup()
    expect(document.activeElement).toBe(cancel)
  })

  // daisyUI fades the modal in from visibility:hidden over 0.3s, and a hidden
  // button refuses focus, so the hook tries again as transitions end.
  function setupWhileFadingIn() {
    const realFocus = HTMLElement.prototype.focus
    let fading = true
    const spy = vi.spyOn(HTMLElement.prototype, "focus").mockImplementation(function (...args) {
      if (fading && this.matches("[data-confirm-dialog-cancel]")) return
      return realFocus.apply(this, args)
    })
    const parts = setup()
    return { ...parts, finishFading: () => { fading = false }, spy }
  }

  it("focuses Cancel once the fade-in transition ends", () => {
    const { el, cancel, finishFading, spy } = setupWhileFadingIn()
    expect(document.activeElement).not.toBe(cancel)

    finishFading()
    el.dispatchEvent(new Event("transitionend"))

    expect(document.activeElement).toBe(cancel)
    spy.mockRestore()
  })

  it("keeps trying across transitions that end while still hidden", () => {
    const { el, cancel, finishFading, spy } = setupWhileFadingIn()

    el.dispatchEvent(new Event("transitionend"))
    expect(document.activeElement).not.toBe(cancel)

    finishFading()
    el.dispatchEvent(new Event("transitionend"))
    expect(document.activeElement).toBe(cancel)
    spy.mockRestore()
  })

  it("does not pull focus back if the person moved within the dialog while it faded in", () => {
    const { el, cancel, finishFading, spy } = setupWhileFadingIn()
    const confirm = el.querySelectorAll("button")[1]
    confirm.focus()

    finishFading()
    el.dispatchEvent(new Event("transitionend"))

    expect(document.activeElement).toBe(confirm)
    expect(document.activeElement).not.toBe(cancel)
    spy.mockRestore()
  })

  it("stops steering focus once Cancel has had it", () => {
    const { el, cancel } = setup()
    cancel.blur()

    // e.g. a button's hover transition ending later
    el.dispatchEvent(new Event("transitionend"))

    expect(document.activeElement).toBe(document.body)
  })

  it("turns Escape into a Cancel click instead of closing the dialog itself", () => {
    const { el, cancel } = setup()
    const onCancel = vi.fn()
    cancel.addEventListener("click", onCancel)

    const event = new Event("cancel", { cancelable: true })
    el.dispatchEvent(event)

    expect(event.defaultPrevented).toBe(true)
    expect(onCancel).toHaveBeenCalledTimes(1)
  })

  it("returns focus to the button that opened it when it goes away", () => {
    const { hook, el, trigger } = setup()
    el.remove()

    hook.destroyed()

    expect(document.activeElement).toBe(trigger)
  })

  it("leaves focus alone when the opening button is gone too", () => {
    const { hook, el, trigger } = setup()
    trigger.remove()
    el.remove()

    expect(() => hook.destroyed()).not.toThrow()
    expect(document.activeElement).toBe(document.body)
  })
})
