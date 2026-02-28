/**
 * Tests for like.js - Like button toggle logic
 *
 * Run with: npm test (from assets/ directory)
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { initLikeButtons } from "./like.js";

// Helper to create the DOM structure used by the like section
function createLikeSection({
  liked = false,
  authenticated = true,
  likerCount = 0,
} = {}) {
  const avatarsHtml =
    likerCount > 0
      ? `<div id="like-avatars" class="flex -space-x-2">${'<div class="avatar"><div class="w-6 rounded-full"><img src="/avatar.jpg" /></div></div>'.repeat(Math.min(likerCount, 5))}${likerCount > 5 ? `<span id="like-overflow" class="text-sm ml-1">+${likerCount - 5} more</span>` : ""}</div>`
      : `<div id="like-avatars" class="flex -space-x-2"></div>`;

  document.body.innerHTML = `
    <meta name="csrf-token" content="test-csrf-token" />
    <div id="like-section" data-object-uri="https://example.com/checkins/abc123" data-liked="${liked}">
      <button id="like-btn" aria-label="${liked ? "Unlike" : "Like"}" ${authenticated ? "" : "disabled"}>
        <span id="like-icon">
          <span class="${liked ? "hero-heart-solid" : "hero-heart"} w-6 h-6 text-error"></span>
        </span>
        <span id="like-spinner" hidden>
          <span class="hero-arrow-path w-5 h-5 animate-spin"></span>
        </span>
      </button>
      ${liked ? `<span id="like-count" class="text-sm">${likerCount}</span>` : '<span id="like-count" class="text-sm" hidden>0</span>'}
      ${avatarsHtml}
    </div>
  `;
}

describe("initLikeButtons", () => {
  let fetchMock;

  beforeEach(() => {
    fetchMock = vi.fn();
    global.fetch = fetchMock;
    global.Intl = {
      DateTimeFormat: () => ({
        resolvedOptions: () => ({ timeZone: "America/New_York" }),
      }),
    };
  });

  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
  });

  it("does nothing when no #like-section is present", () => {
    document.body.innerHTML = "<p>No like section here</p>";
    expect(() => initLikeButtons()).not.toThrow();
  });

  it("does nothing when like button is disabled (unauthenticated)", () => {
    createLikeSection({ authenticated: false });
    initLikeButtons();

    const btn = document.getElementById("like-btn");
    // No fetch should occur even if clicked (button is disabled, initLikeButtons returns early)
    btn.click();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("sends POST /api/likes when not liked", async () => {
    createLikeSection({ liked: false });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalled());

    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/likes");
    expect(options.method).toBe("POST");
    expect(JSON.parse(options.body).object_uri).toBe(
      "https://example.com/checkins/abc123",
    );
    expect(JSON.parse(options.body).published_tz).toBe("America/New_York");
    expect(options.headers["x-csrf-token"]).toBe("test-csrf-token");
  });

  it("sends DELETE /api/likes when already liked", async () => {
    createLikeSection({ liked: true });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: false, count: 0 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalled());

    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("/api/likes");
    expect(options.method).toBe("DELETE");
  });

  it("updates count and shows it when liked", async () => {
    createLikeSection({ liked: false });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      const countEl = document.getElementById("like-count");
      expect(countEl.textContent).toBe("1");
      expect(countEl.hasAttribute("hidden")).toBe(false);
    });
  });

  it("hides count when unliked and count reaches zero", async () => {
    createLikeSection({ liked: true });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: false, count: 0 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      const countEl = document.getElementById("like-count");
      expect(countEl.textContent).toBe("0");
      expect(countEl.hasAttribute("hidden")).toBe(true);
    });
  });

  it("swaps icon to solid when liked", async () => {
    createLikeSection({ liked: false });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      const iconSpan = document.querySelector("#like-icon span");
      expect(iconSpan.className).toContain("hero-heart-solid");
      expect(iconSpan.className).not.toContain("hero-heart ");
    });
  });

  it("swaps icon to outline when unliked", async () => {
    createLikeSection({ liked: true });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: false, count: 0 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      const iconSpan = document.querySelector("#like-icon span");
      expect(iconSpan.className).toContain("hero-heart");
      expect(iconSpan.className).not.toContain("hero-heart-solid");
    });
  });

  it("updates aria-label to Unlike when liked", async () => {
    createLikeSection({ liked: false });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      expect(
        document.getElementById("like-btn").getAttribute("aria-label"),
      ).toBe("Unlike");
    });
  });

  it("re-enables button after successful response", async () => {
    createLikeSection({ liked: false });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });

    initLikeButtons();
    const btn = document.getElementById("like-btn");
    btn.click();

    await vi.waitFor(() => {
      expect(btn.disabled).toBe(false);
    });
  });

  it("re-enables button even when fetch throws an error", async () => {
    createLikeSection({ liked: false });
    // Use mockImplementation so the rejection happens lazily (inside like.js try/catch)
    // rather than creating a pre-rejected Promise that vitest tracks as unhandled.
    fetchMock.mockImplementation(async () => {
      throw new Error("Network error");
    });

    initLikeButtons();
    const btn = document.getElementById("like-btn");
    btn.click();

    await vi.waitFor(() => {
      expect(btn.disabled).toBe(false);
    });
  });

  it("hides spinner and shows icon after response", async () => {
    createLikeSection({ liked: false });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      expect(
        document.getElementById("like-spinner").hasAttribute("hidden"),
      ).toBe(true);
      expect(document.getElementById("like-icon").hasAttribute("hidden")).toBe(
        false,
      );
    });
  });

  it("supports re-like after unlike (sends POST after DELETE)", async () => {
    createLikeSection({ liked: false });

    // First click: like
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });
    // Second click: unlike
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ liked: false, count: 0 }),
    });
    // Third click: re-like
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ liked: true, count: 1 }),
    });

    initLikeButtons();
    const btn = document.getElementById("like-btn");

    btn.click();
    await vi.waitFor(() => expect(btn.disabled).toBe(false));

    btn.click();
    await vi.waitFor(() => expect(btn.disabled).toBe(false));

    btn.click();
    await vi.waitFor(() => expect(btn.disabled).toBe(false));

    const methods = fetchMock.mock.calls.map(([, opts]) => opts.method);
    expect(methods).toEqual(["POST", "DELETE", "POST"]);

    expect(document.getElementById("like-count").textContent).toBe("1");
    expect(document.getElementById("like-count").hasAttribute("hidden")).toBe(
      false,
    );
  });

  it("populates avatars when likers are returned", async () => {
    createLikeSection({ liked: false });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({
        liked: true,
        count: 2,
        total: 2,
        likers: [
          { avatar_url: "/avatars/alice.jpg", display_name: "Alice" },
          { avatar_url: "/avatars/bob.jpg", display_name: "Bob" },
        ],
      }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      const avatarsEl = document.getElementById("like-avatars");
      const imgs = avatarsEl.querySelectorAll("img");
      expect(imgs.length).toBe(2);
      expect(imgs[0].src).toContain("alice.jpg");
      expect(imgs[1].src).toContain("bob.jpg");
      expect(avatarsEl.querySelector('[id="like-overflow"]')).toBeNull();
    });
  });

  it("shows overflow label when more than 5 likers", async () => {
    createLikeSection({ liked: false });
    const likers = Array.from({ length: 5 }, (_, i) => ({
      avatar_url: `/avatars/${i}.jpg`,
      display_name: `Person ${i}`,
    }));
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: true, count: 8, total: 8, likers }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      const avatarsEl = document.getElementById("like-avatars");
      const overflow = avatarsEl.querySelector("#like-overflow");
      expect(overflow).not.toBeNull();
      expect(overflow.textContent).toBe("+3 more");
    });
  });

  it("clears avatars when count drops to zero", async () => {
    createLikeSection({ liked: true, likerCount: 1 });
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ liked: false, count: 0, total: 0, likers: [] }),
    });

    initLikeButtons();
    document.getElementById("like-btn").click();

    await vi.waitFor(() => {
      const avatarsEl = document.getElementById("like-avatars");
      expect(avatarsEl.querySelectorAll("img").length).toBe(0);
    });
  });
});
