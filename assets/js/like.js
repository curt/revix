/**
 * Like button toggle logic.
 *
 * Finds the #like-section element on the page and attaches a click handler
 * to the #like-btn button. Sends POST/DELETE to /api/likes and updates the
 * heart icon, like count, and liker avatars based on the response.
 *
 * The button is disabled (via the `disabled` attribute) for unauthenticated
 * users, so no action is taken in that case.
 */
export function initLikeButtons() {
  const section = document.getElementById("like-section");
  if (!section) return;

  const btn = document.getElementById("like-btn");
  if (!btn || btn.disabled) return;

  const spinner = document.getElementById("like-spinner");
  const iconWrapper = document.getElementById("like-icon");
  const countEl = document.getElementById("like-count");
  const avatarsEl = document.getElementById("like-avatars");
  const objectUri = section.dataset.objectUri;
  const csrfMeta = document.querySelector("meta[name='csrf-token']");
  const csrfToken = csrfMeta ? csrfMeta.getAttribute("content") : "";
  let liked = section.dataset.liked === "true";

  function updateIcon(isLiked) {
    const span = iconWrapper ? iconWrapper.querySelector("span") : null;
    if (!span) return;
    if (isLiked) {
      span.className = span.className
        .split(" ")
        .map((c) => (c === "hero-heart" ? "hero-heart-solid" : c))
        .join(" ");
    } else {
      span.className = span.className
        .split(" ")
        .map((c) => (c === "hero-heart-solid" ? "hero-heart" : c))
        .join(" ");
    }
    btn.setAttribute("aria-label", isLiked ? "Unlike" : "Like");
  }

  function updateAvatars(likers, total) {
    if (!avatarsEl) return;
    avatarsEl.innerHTML = "";
    likers.forEach((liker) => {
      const wrapper = document.createElement("div");
      wrapper.className = "avatar";
      wrapper.title = liker.display_name || "";
      const inner = document.createElement("div");
      inner.className = "w-6 rounded-full";
      const img = document.createElement("img");
      img.src = liker.avatar_url;
      img.alt = liker.display_name || "";
      inner.appendChild(img);
      wrapper.appendChild(inner);
      avatarsEl.appendChild(wrapper);
    });
    // Show "+N more" if there are more than 5 likers
    if (total > 5) {
      const overflow = document.createElement("span");
      overflow.id = "like-overflow";
      overflow.className = "text-sm ml-1";
      overflow.textContent = `+${total - 5} more`;
      avatarsEl.appendChild(overflow);
    }
  }

  btn.addEventListener("click", async () => {
    btn.disabled = true;
    if (iconWrapper) iconWrapper.setAttribute("hidden", "");
    if (spinner) spinner.removeAttribute("hidden");

    const method = liked ? "DELETE" : "POST";
    try {
      const res = await fetch("/api/likes", {
        method,
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "x-csrf-token": csrfToken,
        },
        body: JSON.stringify({
          object_uri: objectUri,
          published_tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }),
      });
      if (res.ok) {
        const data = await res.json();
        liked = data.liked;
        if (countEl) {
          countEl.textContent = data.count;
          if (data.count > 0) {
            countEl.removeAttribute("hidden");
          } else {
            countEl.setAttribute("hidden", "");
          }
        }
        updateAvatars(data.likers || [], data.total || data.count);
        updateIcon(liked);
      }
    } catch (_err) {
      // Network or server error: silently restore button state
    } finally {
      if (spinner) spinner.setAttribute("hidden", "");
      if (iconWrapper) iconWrapper.removeAttribute("hidden");
      btn.disabled = false;
    }
  });
}
