/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";

  // While a title is typed, the threads it resembles (the same bounded,
  // permission-aware autocomplete the search box uses), so a discussion
  // already open is found before a second one is started.
  const delay = 400;
  const minimum = 3;
  const shown = 5;

  const render = (region, list, suggestions) => {
    const items = suggestions
      .filter((suggestion) => suggestion.entity_type === "thread" && suggestion.entity_id)
      .slice(0, shown)
      .map((suggestion) => {
        const item = document.createElement("li");
        const link = document.createElement("a");
        link.href = region.dataset.threadBase.replace("THREAD_ID", suggestion.entity_id);
        link.textContent = suggestion.title || "";
        item.appendChild(link);
        return item;
      });
    list.replaceChildren(...items);
    region.hidden = items.length === 0;
  };

  const initialize = () => {
    document.querySelectorAll("[data-similar-threads]").forEach((region) => {
      if (region.dataset.ready) return;
      region.dataset.ready = "true";
      const form = region.closest("form");
      const title = form && form.elements.namedItem(region.dataset.field || "title");
      const list = region.querySelector("[data-similar-list]");
      if (!title || !list) return;
      let timer = null;
      let controller = null;
      let sequence = 0;

      const lookup = async () => {
        const query = title.value.trim();
        if (query.length < minimum) {
          render(region, list, []);
          return;
        }
        if (controller) controller.abort();
        controller = new AbortController();
        const current = ++sequence;
        try {
          const url = `${region.dataset.url}?q=${encodeURIComponent(query)}&limit=${shown}`;
          const response = await fetch(url, {
            credentials: "same-origin",
            headers: { Accept: "application/json" },
            signal: controller.signal,
          });
          if (!response.ok) throw new Error("similar threads refused");
          const result = await response.json();
          if (current !== sequence) return;
          render(region, list, Array.isArray(result.suggestions) ? result.suggestions : []);
        } catch (error) {
          if (error.name !== "AbortError" && current === sequence) render(region, list, []);
        }
      };

      title.addEventListener("input", () => {
        clearTimeout(timer);
        timer = setTimeout(lookup, delay);
      });
      if (title.value.trim().length >= minimum) lookup();
    });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize);
  } else {
    initialize();
  }
  document.addEventListener("htmx:afterSwap", initialize);
})();
