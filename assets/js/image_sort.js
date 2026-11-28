/**
 * ImageSort LiveView hook — reorder image upload entries by dragging (SortableJS)
 * or with each card's Move earlier / Move later buttons.
 *
 * Mounted on the photos container. Cards carry `data-ref` (pending uploads) or
 * `data-image-id` (saved images). After a drag or a button press, reads the cards
 * in DOM order and pushes "reorder_images" to the LiveView with the new order as a
 * list of `{ref: "…"}` or `{image_id: "…"}` objects.
 */
import Sortable from "sortablejs"

const CARD = "[data-ref], [data-image-id]"

export function createImageSortHook() {
  return {
    mounted() {
      this.sortable = new Sortable(this.el, {
        handle: "[aria-hidden='true']",
        animation: 150,
        ghostClass: "opacity-40",
        onEnd: () => this.pushOrder()
      })

      this.el.addEventListener("click", e => {
        const button = e.target.closest("[data-photo-move]")
        if (!button || !this.el.contains(button)) return

        if (moveCard(button.closest(CARD), button.dataset.photoMove)) {
          button.focus()
          this.pushOrder()
        }
      })
    },

    pushOrder() {
      const order = Array.from(this.el.children)
        .map(el => {
          if (el.dataset.ref) return { ref: el.dataset.ref }
          if (el.dataset.imageId) return { image_id: el.dataset.imageId }
          return null
        })
        .filter(Boolean)
      this.pushEvent("reorder_images", { order })
    },

    destroyed() {
      if (this.sortable) {
        this.sortable.destroy()
        this.sortable = null
      }
    }
  }
}

// Swaps a card with its neighbour in that direction, skipping rows that aren't
// cards (such as upload errors). Returns false at either end of the list.
function moveCard(card, direction) {
  const neighbour = nextCard(card, direction)
  if (!neighbour) return false

  if (direction === "earlier") neighbour.before(card)
  else neighbour.after(card)
  return true
}

function nextCard(card, direction) {
  const step = direction === "earlier" ? "previousElementSibling" : "nextElementSibling"
  let el = card[step]
  while (el && !el.matches(CARD)) el = el[step]
  return el
}
