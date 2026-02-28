/**
 * Comment inline edit logic and timezone injection.
 *
 * - Sets the published_tz hidden input from the browser's timezone.
 * - Edit pencil click → hides the comment display, shows the edit form.
 * - Cancel click → restores display, hides form.
 * - Edit form submit → PUT /notes/:id via fetch, updates display with returned HTML.
 */
function updateCharCount(textarea) {
  const counter = textarea.nextElementSibling;
  if (!counter || !counter.hasAttribute("data-char-count")) return;
  const len = textarea.value.length;
  const max = textarea.dataset.max;
  counter.textContent = max ? `${len} / ${max}` : `${len}`;
  counter.classList.toggle("text-error", !!max && len > parseInt(max, 10));
}

export function initComments() {
  // Inject browser timezone into the new-comment form
  const tzInput = document.getElementById("comment-tz");
  if (tzInput) {
    tzInput.value = Intl.DateTimeFormat().resolvedOptions().timeZone;
  }

  // Character count meters
  document.querySelectorAll("[data-char-counter]").forEach((textarea) => {
    updateCharCount(textarea);
    textarea.addEventListener("input", () => updateCharCount(textarea));
  });

  const csrfMeta = document.querySelector("meta[name='csrf-token']");
  const csrfToken = csrfMeta ? csrfMeta.getAttribute("content") : "";

  // Edit button: show form, hide display
  document.querySelectorAll("[data-edit-comment]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.dataset.editComment;
      document.getElementById(`comment-display-${id}`).classList.add("hidden");
      document
        .getElementById(`comment-edit-form-${id}`)
        .classList.remove("hidden");
    });
  });

  // Cancel button: restore display, hide form
  document.querySelectorAll("[data-cancel-edit]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const id = btn.dataset.cancelEdit;
      document
        .getElementById(`comment-display-${id}`)
        .classList.remove("hidden");
      document
        .getElementById(`comment-edit-form-${id}`)
        .classList.add("hidden");
    });
  });

  // Delete button: DELETE /notes/:id, remove comment from DOM
  document.querySelectorAll("[data-delete-comment]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!window.confirm("Delete this comment?")) return;

      const id = btn.dataset.deleteComment;

      try {
        const res = await fetch(`/notes/${id}`, {
          method: "DELETE",
          headers: {
            Accept: "application/json",
            "x-csrf-token": csrfToken,
          },
        });

        if (res.ok) {
          document.getElementById(`comment-${id}`)?.remove();
        } else {
          alert("Could not delete comment.");
        }
      } catch (_err) {
        // Network error: silently ignore
      }
    });
  });

  // Edit form submit: PUT /notes/:id, update display with returned HTML
  document.querySelectorAll("[data-comment-id]").forEach((form) => {
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const id = form.dataset.commentId;
      const content = form.querySelector("textarea").value;

      try {
        const res = await fetch(`/notes/${id}`, {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
            Accept: "application/json",
            "x-csrf-token": csrfToken,
          },
          body: JSON.stringify({ note: { content } }),
        });

        if (res.ok) {
          const data = await res.json();
          const displayEl = document.getElementById(`comment-display-${id}`);
          displayEl.innerHTML = data.content_html;
          displayEl.classList.remove("hidden");
          form.classList.add("hidden");
        } else {
          const data = await res.json().catch(() => ({}));
          const msg = data.errors
            ? Object.values(data.errors).flat().join(", ")
            : "Could not save comment.";
          alert(msg);
        }
      } catch (_err) {
        // Network error: silently ignore, form remains open
      }
    });
  });
}
