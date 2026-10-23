/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const italian = document.documentElement.lang.startsWith("it");
  const label = (en, it) => italian ? it : en;
  let active;
  const states = new WeakMap();
  const initialize = () => {
    if (active && !active.section.isConnected) {
      active.placeholder.remove();
      active = null;
    }
    const section = document.querySelector(".thread #reply.composer");
    if (!section || states.has(section)) return;
    const field = section.querySelector('textarea[name="body_source"]');
    const heading = section.querySelector("#reply-heading");
    if (!field || !heading) return;
    const controls = document.createElement("div");
    controls.className = "composer-workspace-controls";
    controls.setAttribute("role", "group");
    controls.setAttribute("aria-label", label("Reply options", "Opzioni di risposta"));
    const dock = document.createElement("button");
    const minimize = document.createElement("button");
    [dock, minimize].forEach(button => {
      button.type = "button";
      button.className = "button--quiet button--small";
      controls.append(button);
    });
    dock.textContent = label("Write while reading", "Scrivi mentre leggi");
    dock.setAttribute("aria-pressed", "false");
    minimize.textContent = label("Minimize", "Riduci");
    minimize.hidden = true;
    minimize.setAttribute("aria-expanded", "true");
    heading.after(controls);
    const placeholder = document.createElement("div");
    placeholder.className = "composer-workspace-placeholder";
    placeholder.setAttribute("aria-hidden", "true");
    const state = { section, placeholder };
    states.set(section, state);
    const expand = () => {
      section.classList.remove("composer--minimized");
      minimize.textContent = label("Minimize", "Riduci");
      minimize.setAttribute("aria-expanded", "true");
    };
    state.open = () => {
      if (!section.classList.contains("composer--docked")) {
        placeholder.style.blockSize = `${section.getBoundingClientRect().height}px`;
        section.before(placeholder);
        section.classList.add("composer--docked");
      }
      active = state;
      expand();
      dock.textContent = label("Write in the page", "Scrivi nella pagina");
      dock.setAttribute("aria-pressed", "true");
      minimize.hidden = false;
    };
    dock.addEventListener("click", () => {
      if (!section.classList.contains("composer--docked")) state.open();
      else {
        section.classList.remove("composer--docked");
        expand();
        placeholder.remove();
        dock.textContent = label("Write while reading", "Scrivi mentre leggi");
        dock.setAttribute("aria-pressed", "false");
        minimize.hidden = true;
        active = null;
        section.scrollIntoView({ block: "nearest" });
      }
    });
    const toggle = () => {
      if (section.classList.contains("composer--minimized")) {
        expand();
        field.focus({ preventScroll: true });
      } else {
        section.classList.add("composer--minimized");
        minimize.textContent = label("Continue writing", "Continua a scrivere");
        minimize.setAttribute("aria-expanded", "false");
        minimize.focus({ preventScroll: true });
      }
    };
    minimize.addEventListener("click", toggle);
    section.addEventListener("keydown", event => {
      if (event.key === "Escape" && section.classList.contains("composer--docked") &&
          !section.classList.contains("composer--minimized") && !event.defaultPrevented) {
        event.preventDefault();
        toggle();
      }
    });
    field.addEventListener("composer:reveal", () => state.open());
    // Selection quoting focuses the existing field: reveal it if minimized.
    field.addEventListener("focus", () => { if (active === state) expand(); });
  };
  document.addEventListener("click", event => {
    const link = event.target.closest('a[href="#reply-body"]');
    if (!link || event.button || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    const section = document.querySelector(".thread #reply.composer");
    const state = section && states.get(section);
    if (!state) return;
    event.preventDefault();
    state.open();
    section.querySelector('textarea[name="body_source"]').focus({ preventScroll: true });
  });
  initialize();
  document.addEventListener("htmx:afterSwap", initialize);
  document.addEventListener("htmx:oobAfterSwap", initialize);
})();
