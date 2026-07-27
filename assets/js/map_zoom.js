export const MAX_LOCKED_MIN_ZOOM = 12

function boundsFitZoom(map, bounds, options) {
  const [x, y] = options.padding || [0, 0]
  return map.getBoundsZoom(bounds, false, [x * 2, y * 2])
}

export function fitBoundsAndLockZoom(map, bounds, options) {
  map.fitBounds(bounds, options)
  map.setMinZoom(Math.min(map.getZoom(), MAX_LOCKED_MIN_ZOOM))
}

export function setupResizeRelock(map, getBounds, options) {
  const relock = () => {
    const fitZoom = boundsFitZoom(map, getBounds(), options)
    map.setMinZoom(Math.min(fitZoom, MAX_LOCKED_MIN_ZOOM))
  }
  window.addEventListener("resize", relock)
  return relock
}
