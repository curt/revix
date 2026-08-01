/**
 * InfiniteScroll LiveView hook — observes a sentinel element and pushes
 * "load_more" to the LiveView when it scrolls into view. Guards against
 * firing again while a page is already in flight: `loading` is set on
 * trigger and cleared in the pushEvent reply callback, since the sentinel's
 * own markup never changes between pages (empty div, same id/hook), so
 * LiveView's diff can skip re-patching it and `updated()` won't reliably fire.
 */
export function createInfiniteScrollHook() {
  return {
    mounted() {
      this.loading = false
      this.observer = new IntersectionObserver(([entry]) => {
        if (entry.isIntersecting && !this.loading) {
          this.loading = true
          this.pushEvent("load_more", {}, () => {
            this.loading = false
          })
        }
      }, { rootMargin: "200px" })
      this.observer.observe(this.el)
    },

    destroyed() {
      this.observer?.disconnect()
    }
  }
}
