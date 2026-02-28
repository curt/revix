/**
 * Tests for companions.js - Companion search and chip management
 *
 * Run with: npm test (from assets/ directory)
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { initCompanionSearch } from "./companions.js";

const CSRF = "test-csrf-token";

function createCompanionSection({ existingCompanions = [] } = {}) {
  const chipsHtml = existingCompanions
    .map(
      (c) =>
        `<div class="badge badge-lg gap-1" data-person-uri="${c.uri}">
          <img src="${c.avatar_url}" class="w-4 h-4 rounded-full" />
          ${c.display_name || c.username}
          <button type="button" class="companion-remove ml-1" data-person-uri="${c.uri}" aria-label="Remove companion">&times;</button>
        </div>`,
    )
    .join("");

  document.body.innerHTML = `
    <meta name="csrf-token" content="${CSRF}" />
    <div id="companion-section" data-entry-uri="https://example.com/entries/abc123">
      <input type="text" id="companion-search" autocomplete="off" />
      <ul id="companion-suggestions" class="hidden"></ul>
      <div id="companion-chips">${chipsHtml}</div>
    </div>
  `;
}

function mockFetchJson(data, status = 200) {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: () => Promise.resolve(data),
  });
}

describe("initCompanionSearch", () => {
  let fetchMock;

  beforeEach(() => {
    fetchMock = vi.fn();
    global.fetch = fetchMock;
    vi.useFakeTimers();
  });

  afterEach(() => {
    document.body.innerHTML = "";
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("does nothing when #companion-section is absent", () => {
    document.body.innerHTML = "<p>no section</p>";
    expect(() => initCompanionSearch()).not.toThrow();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("does nothing when #companion-search input is absent", () => {
    document.body.innerHTML = `
      <div id="companion-section" data-entry-uri="https://example.com/e/1">
        <ul id="companion-suggestions" class="hidden"></ul>
        <div id="companion-chips"></div>
      </div>
    `;
    expect(() => initCompanionSearch()).not.toThrow();
  });

  it("does not fire search for empty input", async () => {
    createCompanionSection();
    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(400);

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("fires a debounced search after DEBOUNCE_MS", async () => {
    createCompanionSection();
    fetchMock.mockResolvedValue({ ok: true, json: () => Promise.resolve([]) });
    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "alice";
    input.dispatchEvent(new Event("input"));

    // Not yet
    expect(fetchMock).not.toHaveBeenCalled();

    vi.advanceTimersByTime(300);
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/people/search?q=alice",
      expect.objectContaining({
        headers: expect.objectContaining({ "x-csrf-token": CSRF }),
      }),
    );
  });

  it("does not fire search before debounce delay elapses", () => {
    createCompanionSection();
    fetchMock.mockResolvedValue({ ok: true, json: () => Promise.resolve([]) });
    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "alice";
    input.dispatchEvent(new Event("input"));

    vi.advanceTimersByTime(200);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("shows a suggestion list when results are returned", async () => {
    createCompanionSection();
    const people = [
      {
        uri: "https://example.com/u/1",
        display_name: "Alice",
        username: "alice",
        avatar_url: "/a.jpg",
      },
    ];
    fetchMock.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve(people),
    });
    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "alice";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(300);

    await vi.runAllTimersAsync();

    const suggestions = document.getElementById("companion-suggestions");
    expect(suggestions.classList.contains("hidden")).toBe(false);
    expect(suggestions.children.length).toBe(1);
  });

  it("hides suggestions when search returns empty", async () => {
    createCompanionSection();
    fetchMock.mockResolvedValue({ ok: true, json: () => Promise.resolve([]) });
    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "zzz";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(300);
    await vi.runAllTimersAsync();

    const suggestions = document.getElementById("companion-suggestions");
    expect(suggestions.classList.contains("hidden")).toBe(true);
  });

  it("adds a chip and sends POST when a suggestion is selected", async () => {
    createCompanionSection();
    const person = {
      uri: "https://example.com/u/2",
      display_name: "Bob",
      username: "bob",
      avatar_url: "/b.jpg",
    };

    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([person]),
      }) // search
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve({ companions: [person], count: 1, total: 1 }),
      }); // POST

    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "bob";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(300);

    // Wait for suggestions to appear
    await vi.waitFor(() => {
      const suggestions = document.getElementById("companion-suggestions");
      expect(suggestions.classList.contains("hidden")).toBe(false);
    });

    document
      .getElementById("companion-suggestions")
      .querySelector("li")
      .click();

    // Wait for chip to appear after POST resolves
    await vi.waitFor(() => {
      const chips = document.getElementById("companion-chips");
      expect(chips.children.length).toBe(1);
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/entry_people",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("does not add a duplicate chip when companion is already in list", async () => {
    const person = {
      uri: "https://example.com/u/3",
      display_name: "Carol",
      username: "carol",
      avatar_url: "/c.jpg",
    };
    createCompanionSection({ existingCompanions: [person] });

    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([person]),
      }) // search
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve({ companions: [person], count: 1, total: 1 }),
      }); // POST

    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "carol";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(300);

    await vi.waitFor(() => {
      const suggestions = document.getElementById("companion-suggestions");
      expect(suggestions.classList.contains("hidden")).toBe(false);
    });

    document
      .getElementById("companion-suggestions")
      .querySelector("li")
      .click();

    // Wait for POST to resolve, then check no duplicate
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));

    const chips = document.getElementById("companion-chips");
    // Still only 1 chip (no duplicate added)
    expect(chips.children.length).toBe(1);
  });

  it("removes a chip and sends DELETE when remove button is clicked", async () => {
    const person = {
      uri: "https://example.com/u/4",
      display_name: "Dan",
      username: "dan",
      avatar_url: "/d.jpg",
    };
    createCompanionSection({ existingCompanions: [person] });
    fetchMock.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ companions: [], count: 0, total: 0 }),
    });

    initCompanionSearch();

    const removeBtn = document.querySelector(".companion-remove");
    removeBtn.click();

    // Wait for DELETE to be sent and chip to be removed
    await vi.waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith(
        "/api/entry_people",
        expect.objectContaining({ method: "DELETE" }),
      );
    });

    await vi.waitFor(() => {
      const chips = document.getElementById("companion-chips");
      expect(chips.children.length).toBe(0);
    });
  });

  it("silently handles search network errors", async () => {
    createCompanionSection();
    fetchMock.mockRejectedValue(new Error("Network error"));
    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "error";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(300);

    // Wait for fetch to be called; should not throw
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalled());
  });

  it("silently handles POST errors when adding a companion", async () => {
    createCompanionSection();
    const person = {
      uri: "https://example.com/u/5",
      display_name: "Eve",
      username: "eve",
      avatar_url: "/e.jpg",
    };

    fetchMock
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([person]),
      }) // search
      .mockRejectedValueOnce(new Error("POST failed")); // POST

    initCompanionSearch();

    const input = document.getElementById("companion-search");
    input.value = "eve";
    input.dispatchEvent(new Event("input"));
    vi.advanceTimersByTime(300);

    await vi.waitFor(() => {
      const suggestions = document.getElementById("companion-suggestions");
      expect(suggestions.classList.contains("hidden")).toBe(false);
    });

    document
      .getElementById("companion-suggestions")
      .querySelector("li")
      .click();

    // Wait for the POST attempt to be made, then verify no chip was added (POST failed)
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    const chips = document.getElementById("companion-chips");
    expect(chips.children.length).toBe(0);
  });

  it("silently handles DELETE errors when removing a companion", async () => {
    const person = {
      uri: "https://example.com/u/6",
      display_name: "Frank",
      username: "frank",
      avatar_url: "/f.jpg",
    };
    createCompanionSection({ existingCompanions: [person] });
    fetchMock.mockRejectedValue(new Error("DELETE failed"));

    initCompanionSearch();

    const removeBtn = document.querySelector(".companion-remove");
    removeBtn.click();

    // Wait for DELETE to be attempted; chip should remain since DELETE failed
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalled());
    const chips = document.getElementById("companion-chips");
    expect(chips.children.length).toBe(1);
  });
});
