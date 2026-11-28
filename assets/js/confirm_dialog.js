/**
 * ConfirmDialog LiveView hook — opens `<.confirm_dialog>` as a real modal.
 *
 * `showModal()` puts the dialog in the top layer, so it is announced and Tab
 * stays inside it. Cancel is focused first, so the safe choice is the default.
 * Escape fires `cancel`; instead of letting the browser close the dialog
 * behind LiveView's back, it clicks Cancel so the server event and target are
 * exactly those of the button. When the server removes the dialog, focus goes
 * back to the button that opened it, if that is still on the page.
 */
export function createConfirmDialogHook() {
  return {
    mounted() {
      this.trigger = document.activeElement
      const cancel = this.el.querySelector("[data-confirm-dialog-cancel]")

      this.el.addEventListener("cancel", e => {
        e.preventDefault()
        cancel.click()
      })

      this.el.showModal()

      // daisyUI fades the modal in from visibility:hidden, and a hidden button
      // refuses focus, so try now and again as each transition ends, until
      // focus is inside the dialog. Never pull it back once it is.
      const focusCancel = () => {
        if (!this.el.contains(document.activeElement)) cancel.focus()
        if (this.el.contains(document.activeElement)) {
          this.el.removeEventListener("transitionend", focusCancel)
        }
      }
      this.el.addEventListener("transitionend", focusCancel)
      focusCancel()
    },

    // Focusing a button that has left the page does nothing.
    destroyed() {
      this.trigger.focus()
    }
  }
}
