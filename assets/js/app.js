// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { createImageSortHook } from "./image_sort.js"
import { createPlaceSearchHook } from "./place_search.js"

const Hooks = {}

Hooks.ImageSort = createImageSortHook()
Hooks.PlaceSearch = createPlaceSearchHook()

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
// if (process.env.NODE_ENV === "development") {
//   window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
//     // Enable server log streaming to client.
//     // Disable with reloader.disableServerLogs()
//     reloader.enableServerLogs()
//
//     // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
//     //
//     //   * click with "c" key pressed to open at caller location
//     //   * click with "d" key pressed to open at function component definition location
//     let keyDown
//     window.addEventListener("keydown", e => keyDown = e.key)
//     window.addEventListener("keyup", _e => keyDown = null)
//     window.addEventListener("click", e => {
//       if(keyDown === "c"){
//         e.preventDefault()
//         e.stopImmediatePropagation()
//         reloader.openEditorAtCaller(e.target)
//       } else if(keyDown === "d"){
//         e.preventDefault()
//         e.stopImmediatePropagation()
//         reloader.openEditorAtDef(e.target)
//       }
//     }, true)
//
//     window.liveReloader = reloader
//   })
// }

// Handle flash close
document.querySelectorAll("[role=alert][data-flash]").forEach((el) => {
  el.addEventListener("click", () => {
    el.setAttribute("hidden", "");
  });
});

import { initLikeButtons } from "./like.js";
document.addEventListener("DOMContentLoaded", initLikeButtons);

import { initComments } from "./comments.js";
document.addEventListener("DOMContentLoaded", initComments);

import { initCompanionSearch } from "./companions.js";
document.addEventListener("DOMContentLoaded", initCompanionSearch);

import L from "leaflet";

// Fix for default marker icons in webpack/esbuild environments
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "/images/marker-icon-2x.png",
  iconUrl: "/images/marker-icon.png",
  shadowUrl: "/images/marker-shadow.png",
});

// Initialize your map when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  const mapElement = document.getElementById("map");
  if (mapElement) {
    const map = L.map("map").setView([0, 0], 2);

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
    }).addTo(map);

    // Define custom red marker icon
    const redIcon = L.icon({
      iconUrl: "/images/marker-icon-2x-red.png",
      shadowUrl: "/images/marker-shadow.png",
      iconSize: [25, 41],
      iconAnchor: [12, 41],
      popupAnchor: [1, -34],
      shadowSize: [41, 41],
    });

    // Fetch GeoJSON data and add to map
    fetch("?geo", {
      headers: {
        Accept: "application/geo+json",
      },
    })
      .then((response) => response.json())
      .then((data) => {
        const geoJsonLayer = L.geoJSON(data, {
          pointToLayer: function (feature, latlng) {
            // Use red marker for focus features
            if (feature.properties.focus) {
              return L.marker(latlng, { icon: redIcon, zIndexOffset: 1000 });
            }
            // Return default blue marker for non-center features
            return L.marker(latlng);
          },
          onEachFeature: function (feature, layer) {
            const props = feature.properties;
            let popupContent = `<div><strong>${props.name}</strong></div>`;
            popupContent += `<div>${feature.geometry.coordinates[1].toFixed(3)}, ${feature.geometry.coordinates[0].toFixed(3)}</div>`;
            popupContent += `<div><a href="${props.url}">Details</a></div>`;
            layer.bindPopup(popupContent);
          },
        }).addTo(map);

        // Fit map bounds to show all markers
        if (data.features.length > 0) {
          map.fitBounds(geoJsonLayer.getBounds(), { padding: [50, 50] });
        }
      })
      .catch((error) => console.error("Error loading GeoJSON:", error));
  }
});
