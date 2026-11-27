import { describe, it, expect } from "vitest"
import { buildPopupContent } from "./map_popup.js"

function feature(properties, coordinates = [-105.12345, 40.98765]) {
  return { properties, geometry: { type: "Point", coordinates } }
}

describe("buildPopupContent", () => {
  it("shows the name, coordinates, and a details link", () => {
    const el = buildPopupContent(feature({ name: "Cafe", url: "https://revix.example/places/1" }))

    expect(el.querySelector("strong").textContent).toBe("Cafe")
    expect(el.textContent).toContain("40.988, -105.123")
    const link = el.querySelector("a")
    expect(link.textContent).toBe("Details")
    expect(link.getAttribute("href")).toBe("https://revix.example/places/1")
  })

  it("renders a hostile name as text, not markup", () => {
    const el = buildPopupContent(feature({ name: '<img src=x onerror="alert(1)">', url: "/p" }))

    expect(el.querySelector("img")).toBeNull()
    expect(el.querySelector("strong").textContent).toBe('<img src=x onerror="alert(1)">')
  })

  it("drops a link whose url is not http(s) or a local path", () => {
    const el = buildPopupContent(feature({ name: "Bad", url: "javascript:alert(1)" }))

    expect(el.querySelector("a")).toBeNull()
  })

  it("drops a protocol-relative link to another host", () => {
    const el = buildPopupContent(feature({ name: "Elsewhere", url: "//evil.example/x" }))

    expect(el.querySelector("a")).toBeNull()
  })

  it("keeps a local path link", () => {
    const el = buildPopupContent(feature({ name: "Local", url: "/places/1" }))

    expect(el.querySelector("a").getAttribute("href")).toBe("/places/1")
  })
})
