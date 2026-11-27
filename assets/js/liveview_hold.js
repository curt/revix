const ROOT = "[data-phx-session]"
const HOLDABLE = "button, input[type=submit], [phx-click]"
const FORM_CONTROL = "input:not([type=submit]), textarea, select"
const PENDING = "[data-phx-ref-loading]"
const HELD_CLASS = "phx-held"

/**
 * installLiveViewHold — holds button clicks and form submits inside a LiveView
 * until that LiveView is ready, then replays them (GH #198).
 *
 * A LiveView is ready when its root carries `phx-connected` and none of its
 * elements carries `data-phx-ref-loading` (set by LiveView for every pending
 * click, change, submit, or hook push). Before the socket joins, or while it
 * reconnects, LiveView silently drops pushes; holding keeps the user's intent.
 *
 * Only the latest action per LiveView is held. The held element gets the
 * `phx-held` class and `aria-busy="true"` for a spinner. If it is removed or
 * disabled by the time the LiveView is ready, the action is dropped.
 *
 * `schedule` defers the readiness re-check (default: requestAnimationFrame) so
 * pushes made by hooks during the join have set their refs first.
 *
 * Returns a teardown function.
 */
export function installLiveViewHold(doc = document, { schedule = cb => requestAnimationFrame(cb) } = {}) {
  const held = new Map()

  const onClick = e => {
    const el = holdableTarget(e.target)
    if (!el) return
    const root = el.closest(ROOT)
    if (!root || isReady(root)) return

    e.preventDefault()
    e.stopImmediatePropagation()
    // A detached or disabled element dispatches no click, so a stale one is a no-op.
    hold(root, { el, replay: () => el.click() })
  }

  const onSubmit = e => {
    const form = e.target
    const root = form.closest?.(ROOT)
    if (!root || isReady(root)) return

    e.preventDefault()
    e.stopImmediatePropagation()
    const submitter = e.submitter
    hold(root, {
      el: submitter || form.querySelector("button:not([type=button]), input[type=submit]") || form,
      replay: () => form.isConnected && form.requestSubmit(submitter?.isConnected ? submitter : undefined),
    })
  }

  const hold = (root, action) => {
    const previous = held.get(root)
    if (previous) unmark(previous.el)
    mark(action.el)
    held.set(root, action)
  }

  const recheck = () => {
    for (const [root, action] of held) {
      if (!isReady(root)) continue
      held.delete(root)
      unmark(action.el)
      action.replay()
    }
  }

  const observer = new MutationObserver(() => {
    if (held.size > 0) schedule(recheck)
  })
  observer.observe(doc.documentElement, {
    subtree: true,
    childList: true,
    attributes: true,
    attributeFilter: ["class", "data-phx-ref-loading"],
  })
  doc.addEventListener("click", onClick, true)
  doc.addEventListener("submit", onSubmit, true)

  return () => {
    observer.disconnect()
    doc.removeEventListener("click", onClick, true)
    doc.removeEventListener("submit", onSubmit, true)
    held.forEach(action => unmark(action.el))
    held.clear()
  }
}

/**
 * preserveHeldState — a LiveView `dom.onBeforeElUpdated` callback that keeps
 * the held marker (and its spinner) on an element across patches.
 */
export function preserveHeldState(fromEl, toEl) {
  if (!fromEl.classList?.contains(HELD_CLASS)) return
  mark(toEl)
}

function holdableTarget(target) {
  if (!(target instanceof Element) || target.matches(FORM_CONTROL)) return null
  return target.closest(HOLDABLE)
}

function isReady(root) {
  return root.classList.contains("phx-connected") && !root.querySelector(PENDING)
}

function mark(el) {
  el.classList.add(HELD_CLASS)
  el.setAttribute("aria-busy", "true")
}

function unmark(el) {
  el.classList.remove(HELD_CLASS)
  el.removeAttribute("aria-busy")
}
