/**
 * preserveTextareaSize — a LiveView `dom.onBeforeElUpdated` callback.
 *
 * Controlled <textarea>s are re-rendered on every phx-change, so morphdom
 * replaces the element and discards the inline `style="height:…"` the browser
 * adds when the user drags the resize handle (GH #176). Before the patch is
 * applied, copy any user-set inline height/width from the live element onto the
 * incoming one so the resize survives.
 *
 * Only acts when the live element already carries an inline dimension (i.e. the
 * user actually resized it) and the incoming markup does not set its own — so a
 * server-driven size change still wins.
 */
export function preserveTextareaSize(fromEl, toEl) {
  if (fromEl.nodeName !== "TEXTAREA") return

  const { height, width } = fromEl.style
  if (height && !toEl.style.height) toEl.style.height = height
  if (width && !toEl.style.width) toEl.style.width = width
}
