/**
 * PlaceSearch LiveView hook — pushes browser datetime/timezone on mount for
 * field pre-filling, and wires the optional "Locate me" button to push
 * geolocation coordinates to the LiveView.
 *
 * The set_defaults push always fires, regardless of whether #locate-btn is
 * present, so the hook works on both the full place-search form and the
 * simpler place-first checkin form.
 *
 * When locating fails, the status says why in plain words (never the
 * browser's raw error) and #locate-fallback, a pointer to Places, appears.
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
      const fallback = this.el.querySelector("#locate-fallback")
      if (!locateBtn) return

      const fail = message => {
        locateStatus.textContent = message
        if (fallback) fallback.hidden = false
      }

      locateBtn.addEventListener("click", () => {
        if (!navigator.geolocation) {
          fail("This browser can't share its location.")
          return
        }
        locateStatus.textContent = "Locating..."
        locateBtn.disabled = true
        navigator.geolocation.getCurrentPosition(
          ({coords: {latitude, longitude, accuracy}}) => {
            locateStatus.textContent = `Located (±${Math.round(accuracy)}m)`
            if (fallback) fallback.hidden = true
            this.pushEvent("locate", {lat: latitude, lon: longitude, accuracy})
          },
          (err) => {
            fail(locationErrorMessage(err))
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

// GeolocationPositionError.PERMISSION_DENIED is 1; POSITION_UNAVAILABLE (2)
// and TIMEOUT (3) both mean "try again".
function locationErrorMessage(err) {
  return err.code === 1
    ? "Location is off for this site. Allow it in your browser and try again."
    : "Couldn't find your location. Try again in a moment."
}
