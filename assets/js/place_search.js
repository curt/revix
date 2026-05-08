/**
 * PlaceSearch LiveView hook — pushes browser datetime/timezone on mount for
 * field pre-filling, and wires the optional "Locate me" button to push
 * geolocation coordinates to the LiveView.
 *
 * The set_defaults push always fires, regardless of whether #locate-btn is
 * present, so the hook works on both the full place-search form and the
 * simpler place-first checkin form.
 */
export function createPlaceSearchHook() {
  return {
    mounted() {
      const now = new Date()
      const pad = n => String(n).padStart(2, "0")
      const localDatetime = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`
      this.pushEvent("set_defaults", {
        local_datetime: localDatetime,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
      })

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
