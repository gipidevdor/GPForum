/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const search = document.querySelector("[data-settings-search]");
  if (!search) return;
  const input = search.querySelector("[data-settings-filter]");
  const groups = [...document.querySelectorAll("[data-settings-group]")];
  const initial = groups.map(group => group.open);
  const form = document.querySelector("[data-admin-configuration]");
  let dirty = form && form.dataset.hasErrors === "1";
  if (form) {
    form.addEventListener("input", () => { dirty = true; });
    form.addEventListener("change", () => { dirty = true; });
    form.addEventListener("submit", () => { dirty = false; });
    window.addEventListener("beforeunload", (event) => {
      if (!dirty) return;
      event.preventDefault();
      event.returnValue = "";
    });
  }
  search.hidden = false;
  input.addEventListener("input", () => {
    const query = input.value.trim().toLocaleLowerCase();
    groups.forEach((group, index) => {
      let count = 0;
      group.querySelectorAll("[data-settings-field]").forEach(field => {
        field.hidden = Boolean(query) && !field.textContent.toLocaleLowerCase().includes(query);
        if (!field.hidden) count++;
      });
      group.hidden = count === 0;
      group.open = query ? count > 0 : initial[index];
    });
    search.querySelector("[data-settings-filter-status]").textContent = groups.every(group => group.hidden) ? search.dataset.noResults : "";
  });
})();
