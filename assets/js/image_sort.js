/**
 * ImageSort LiveView hook — drag-to-reorder image upload entries using SortableJS.
 *
 * Mounted on the photos container. On drag end, reads the `data-ref` (for pending
 * uploads) or `data-image-id` (for existing saved images) attributes from child
 * elements in DOM order and pushes "reorder_images" to the LiveView with the new
 * order as a list of `{ref: "…"}` or `{image_id: "…"}` objects.
 */
import Sortable from "sortablejs"

export function createImageSortHook() {
  return {
    mounted() {
      this.sortable = new Sortable(this.el, {
        handle: "[aria-hidden='true']",
        animation: 150,
        ghostClass: "opacity-40",
        onEnd: () => {
          const order = Array.from(this.el.children)
            .map(el => {
              if (el.dataset.ref) return { ref: el.dataset.ref }
              if (el.dataset.imageId) return { image_id: el.dataset.imageId }
              return null
            })
            .filter(Boolean)
          this.pushEvent("reorder_images", { order })
        }
      })
    },

    destroyed() {
      if (this.sortable) {
        this.sortable.destroy()
        this.sortable = null
      }
    }
  }
}
