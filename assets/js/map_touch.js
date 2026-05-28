export function setupCooperativeTouch(map) {
  const touchCapable =
    "ontouchstart" in window || navigator.maxTouchPoints > 0 || navigator.msMaxTouchPoints > 0

  if (!touchCapable) return

  const container = map.getContainer()
  let hintTimeoutId = null
  const hintStorageKey = "revix:map-two-finger-hint-shown"

  const hint = document.createElement("div")
  hint.textContent = "Use two fingers to move the map"
  hint.className =
    "pointer-events-none absolute left-1/2 top-3 z-[500] hidden -translate-x-1/2 rounded-full border border-base-300 bg-base-100 px-3 py-1 text-xs font-medium text-base-content shadow-sm"
  container.appendChild(hint)

  const showHint = () => {
    if (sessionStorage.getItem(hintStorageKey) === "1") return

    hint.classList.remove("hidden")
    sessionStorage.setItem(hintStorageKey, "1")
    if (hintTimeoutId) clearTimeout(hintTimeoutId)
    hintTimeoutId = window.setTimeout(() => hint.classList.add("hidden"), 1200)
  }

  const disableDrag = () => {
    if (map.dragging.enabled()) map.dragging.disable()
  }

  const maybeEnableDrag = (touches) => {
    if (touches.length >= 2) {
      if (!map.dragging.enabled()) map.dragging.enable()
      hint.classList.add("hidden")
      return
    }

    disableDrag()
  }

  disableDrag()

  container.addEventListener(
    "touchstart",
    (event) => {
      if (event.touches.length === 1) showHint()
      maybeEnableDrag(event.touches)
    },
    { passive: true }
  )

  container.addEventListener(
    "touchmove",
    (event) => {
      maybeEnableDrag(event.touches)
    },
    { passive: true }
  )

  container.addEventListener(
    "touchend",
    (event) => {
      maybeEnableDrag(event.touches)
    },
    { passive: true }
  )

  container.addEventListener(
    "touchcancel",
    () => {
      disableDrag()
    },
    { passive: true }
  )
}
