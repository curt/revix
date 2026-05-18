export function createPlaceNewHook() {
  return {
    mounted() {
      const locateBtn = this.el.querySelector("#locate-btn")
      const locateStatus = this.el.querySelector("#locate-status")
      if (!locateBtn) return

      locateBtn.addEventListener("click", () => {
        if (!navigator.geolocation) {
          locateStatus.textContent = "Geolocation not supported"
          return
        }
        locateStatus.textContent = "Locating..."
        locateBtn.disabled = true
        navigator.geolocation.getCurrentPosition(
          ({coords: {latitude, longitude, accuracy}}) => {
            locateStatus.textContent = `Located (±${Math.round(accuracy)}m)`
            this.pushEvent("locate", {lat: latitude, lon: longitude, accuracy})
          },
          (err) => {
            locateStatus.textContent = `Error: ${err.message}`
            locateBtn.disabled = false
          },
          {enableHighAccuracy: true, timeout: 15000}
        )
      })
    },

    updated() {
      const btn = this.el.querySelector("#locate-btn")
      if (btn) btn.disabled = false
    }
  }
}
