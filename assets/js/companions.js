/**
 * Companion search and chip management.
 *
 * Finds the #companion-section element on the page (which must have a
 * data-entry-uri attribute) and attaches search-as-you-type behaviour to the
 * #companion-search input. Matching people are shown as a dropdown; selecting
 * one adds them as a companion chip and sends POST /api/entry_people.
 * Clicking the × on a chip sends DELETE /api/entry_people and removes the chip.
 */

const DEBOUNCE_MS = 300;

export function initCompanionSearch() {
  const section = document.getElementById("companion-section");
  if (!section) return;

  const searchInput = document.getElementById("companion-search");
  const suggestions = document.getElementById("companion-suggestions");
  const chips = document.getElementById("companion-chips");
  if (!searchInput || !suggestions || !chips) return;

  const entryUri = section.dataset.entryUri;
  const csrfMeta = document.querySelector("meta[name='csrf-token']");
  const csrfToken = csrfMeta ? csrfMeta.getAttribute("content") : "";

  let debounceTimer = null;

  function getHeaders() {
    return {
      "Content-Type": "application/json",
      Accept: "application/json",
      "x-csrf-token": csrfToken,
    };
  }

  function addChip(person) {
    // Prevent duplicate chips (only check direct children of chips container)
    const existing = Array.from(chips.children).find(
      (el) => el.dataset.personUri === person.uri,
    );
    if (existing) return;

    const chip = document.createElement("div");
    chip.className = "badge badge-lg gap-1";
    chip.dataset.personUri = person.uri;

    const img = document.createElement("img");
    img.src = person.avatar_url;
    img.alt = person.display_name || person.username || "";
    img.className = "w-4 h-4 rounded-full";

    const label = document.createTextNode(
      person.display_name || person.username || person.uri,
    );

    const removeBtn = document.createElement("button");
    removeBtn.type = "button";
    removeBtn.className = "companion-remove ml-1";
    removeBtn.dataset.personUri = person.uri;
    removeBtn.setAttribute("aria-label", "Remove companion");
    removeBtn.textContent = "×";
    removeBtn.addEventListener("click", () => {
      removeCompanion(person.uri, chip).catch(() => {});
    });

    chip.appendChild(img);
    chip.appendChild(label);
    chip.appendChild(removeBtn);
    chips.appendChild(chip);
  }

  async function removeCompanion(personUri, chipEl) {
    const res = await fetch("/api/entry_people", {
      method: "DELETE",
      headers: getHeaders(),
      body: JSON.stringify({ entry_uri: entryUri, person_uri: personUri }),
    });
    if (res.ok && chipEl) {
      chipEl.remove();
    }
  }

  function hideSuggestions() {
    suggestions.innerHTML = "";
    suggestions.classList.add("hidden");
  }

  function showSuggestions(people) {
    suggestions.innerHTML = "";
    if (people.length === 0) {
      suggestions.classList.add("hidden");
      return;
    }
    people.forEach((person) => {
      const li = document.createElement("li");
      li.className =
        "flex items-center gap-2 px-3 py-2 cursor-pointer hover:bg-base-200";

      const img = document.createElement("img");
      img.src = person.avatar_url;
      img.alt = person.display_name || person.username || "";
      img.className = "w-6 h-6 rounded-full";

      const span = document.createElement("span");
      span.textContent = person.display_name || person.username || person.uri;

      li.appendChild(img);
      li.appendChild(span);

      li.addEventListener("click", () => {
        hideSuggestions();
        searchInput.value = "";
        fetch("/api/entry_people", {
          method: "POST",
          headers: getHeaders(),
          body: JSON.stringify({ entry_uri: entryUri, person_uri: person.uri }),
        })
          .then((res) => {
            if (res.ok) addChip(person);
          })
          .catch(() => {});
      });

      suggestions.appendChild(li);
    });
    suggestions.classList.remove("hidden");
  }

  searchInput.addEventListener("input", () => {
    clearTimeout(debounceTimer);
    const query = searchInput.value.trim();
    if (query.length === 0) {
      hideSuggestions();
      return;
    }
    debounceTimer = setTimeout(() => {
      fetch(`/api/people/search?q=${encodeURIComponent(query)}`, {
        headers: { Accept: "application/json", "x-csrf-token": csrfToken },
      })
        .then((res) => {
          if (res.ok) return res.json();
          return [];
        })
        .then((people) => {
          showSuggestions(people);
        })
        .catch(() => {});
    }, DEBOUNCE_MS);
  });

  // Close suggestions when clicking outside
  document.addEventListener("click", (e) => {
    if (!section.contains(e.target)) {
      hideSuggestions();
    }
  });

  // Attach remove handlers to server-rendered chips (for edit page pre-populated chips)
  chips.querySelectorAll(".companion-remove").forEach((btn) => {
    const personUri = btn.dataset.personUri;
    const chipEl = btn.parentElement;
    btn.addEventListener("click", () => {
      removeCompanion(personUri, chipEl).catch(() => {});
    });
  });
}
