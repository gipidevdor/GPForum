/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const init = () => {
    document.querySelectorAll("[data-navigation-filter]:not([data-ready])").forEach(filter => {
      filter.dataset.ready = "1";
      const input = filter.querySelector("input");
      const groups = [...document.querySelectorAll("[data-navigation-group]")];
      const initial = groups.map(group => group.open);
      filter.hidden = false;
      input.addEventListener("input", () => {
        const query = input.value.trim().toLocaleLowerCase();
        groups.forEach((group, index) => {
          const groupMatch = query && group.querySelector("summary").textContent.toLocaleLowerCase().includes(query);
          let count = 0;
          group.querySelectorAll("[data-navigation-item]").forEach(item => {
            item.hidden = Boolean(query) && !groupMatch && !item.textContent.toLocaleLowerCase().includes(query);
            if (!item.hidden) count++;
          });
          group.hidden = count === 0;
          group.open = query ? count > 0 : initial[index];
        });
        filter.querySelector("[data-navigation-status]").textContent = groups.every(group => group.hidden) ? filter.dataset.noResults : "";
      });
    });
    document.querySelectorAll("[data-transfer-form]:not([data-ready])").forEach(form => {
      form.dataset.ready = "1";
      const operation = form.elements.operation;
      const target = form.elements.target;
      const title = form.elements.title;
      const sync = () => {
        const split = operation.value === "split";
        const merge = operation.value === "merge";
        form.querySelector("[data-transfer-target]").hidden = split;
        target.required = !split;
        target.disabled = split;
        form.querySelector("[data-transfer-title]").hidden = !split;
        title.required = split;
        title.disabled = !split;
        form.querySelector("[data-transfer-posts]").hidden = merge;
        form.querySelector("[data-transfer-count]").textContent = String(form.querySelectorAll('input[name="post_numbers"]:checked').length);
      };
      form.addEventListener("change", sync);
      sync();
    });
  };
  document.addEventListener("click", event => {
    document.querySelectorAll("[data-account-menu][open], .post-reaction-picker[open]").forEach(menu => {
      if (!menu.contains(event.target)) menu.open = false;
    });
  });
  document.addEventListener("keydown", event => {
    if (event.key !== "Escape") return;
    document.querySelectorAll("[data-account-menu][open], .post-reaction-picker[open]").forEach(menu => {
      menu.open = false;
      menu.querySelector("summary").focus();
    });
  });
  init();
  document.addEventListener("htmx:after:swap", init);
})();
