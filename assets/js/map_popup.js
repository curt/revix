// Place names and URLs in the GeoJSON can come from federated servers, so the
// popup is built from DOM nodes rather than an HTML string.
const SAFE_URL = /^(https?:\/\/|\/(?!\/))/i

export function buildPopupContent(feature) {
  const { name, url } = feature.properties
  const [lon, lat] = feature.geometry.coordinates
  const container = document.createElement("div")

  const nameRow = document.createElement("div")
  const strong = document.createElement("strong")
  strong.textContent = name ?? ""
  nameRow.appendChild(strong)
  container.appendChild(nameRow)

  const coordsRow = document.createElement("div")
  coordsRow.textContent = `${lat.toFixed(3)}, ${lon.toFixed(3)}`
  container.appendChild(coordsRow)

  if (typeof url === "string" && SAFE_URL.test(url)) {
    const linkRow = document.createElement("div")
    const link = document.createElement("a")
    link.href = url
    link.textContent = "Details"
    linkRow.appendChild(link)
    container.appendChild(linkRow)
  }

  return container
}
