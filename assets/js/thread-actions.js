/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const italian = document.documentElement.lang.startsWith("it");
  const label = (en, it) => italian ? it : en;
  const states = new WeakMap();
  const textOfSelection = (post) => {
    const selection = window.getSelection();
    const body = post.querySelector(".forum-post-body");
    if (!selection || selection.isCollapsed || !body ||
      !body.contains(selection.anchorNode) || !body.contains(selection.focusNode)) return "";
    return selection.toString().trim();
  };
  const button = (text, action) => {
    const node = document.createElement("button");
    node.type = "button";
    node.className = "button--quiet";
    node.textContent = text;
    node.addEventListener("click", action);
    return node;
  };
  const copy = async (text, status) => {
    try {
      await navigator.clipboard.writeText(text);
      status.textContent = label("Copied", "Copiato");
    } catch {
      status.textContent = label("Copy unavailable. Select and copy the text or link manually.",
        "Copia non disponibile. Seleziona e copia manualmente il testo o il collegamento.");
    }
  };
  const initialize = () => {
    document.querySelectorAll("#posts .post[id]").forEach((post) => {
      if (states.has(post)) return;
      const state = { selected: "" };
      states.set(post, state);
      const actions = document.createElement("div");
      actions.className = "post-reading-tools";
      actions.setAttribute("role", "group");
      actions.setAttribute("aria-label", label("Reading tools", "Strumenti di lettura"));
      const status = document.createElement("span");
      status.className = "ui-hint";
      status.setAttribute("role", "status");
      const link = new URL(post.dataset.pageUrl || window.location.href, window.location.href);
      link.hash = post.id;
      link.searchParams.delete("quote");
      link.searchParams.delete("reply_to");
      // Each response carries its page cursor, including replies appended by HTMX.
      actions.append(button(label("Copy post link", "Copia link al messaggio"), () => copy(link.href, status)));
      const composer = document.querySelector('#reply form[data-composer] textarea[name="body_source"]');
      // Ignored content is deliberately collapsed, and must not be exposed by
      // adding a reading control outside its disclosure.
      if (composer && !post.querySelector(".post__ignored")) {
        const quote = button(label("Quote selection", "Cita selezione"), () => {
          const field = document.querySelector('#reply form[data-composer] textarea[name="body_source"]');
          const selected = textOfSelection(post) || state.selected;
          state.selected = "";
          if (!field || !selected) {
            status.textContent = label("Select a passage in this message first.", "Seleziona prima un passaggio di questo messaggio.");
            return;
          }
          const quoteText = selected.split(/\r?\n/).map(line => `> ${line}`).join("\n");
          const ordinal = post.querySelector(".post__permalink")?.textContent.trim() || "#";
          const separator = field.value && !field.value.endsWith("\n\n") ? "\n\n" : "";
          const insertion = `${separator}[${ordinal}](${link.href})\n\n${quoteText}\n\n`;
          // Append rather than replacing a selection or an unsaved draft.
          field.setRangeText(insertion, field.value.length, field.value.length, "end");
          field.dispatchEvent(new Event("input", { bubbles: true }));
          field.dispatchEvent(new Event("composer:reveal"));
          field.focus();
          status.textContent = label("Selection added to your reply.", "Selezione aggiunta alla risposta.");
        });
        quote.addEventListener("pointerdown", () => { state.selected = textOfSelection(post); });
        actions.append(quote);
      }
      actions.append(status);
      post.append(actions);
      post.querySelectorAll(".forum-post-body pre").forEach((block) => {
        if (block.closest(".post__ignored")) return;
        const code = block.querySelector("code");
        if (!code) return;
        const tools = document.createElement("div");
        tools.className = "post-code-tools";
        const feedback = document.createElement("span");
        feedback.className = "ui-hint";
        feedback.setAttribute("role", "status");
        tools.append(button(label("Copy code", "Copia codice"), () => copy(code.textContent, feedback)), feedback);
        block.after(tools);
      });
    });
  };
  initialize();
  document.addEventListener("htmx:afterSwap", initialize);
  document.addEventListener("htmx:oobAfterSwap", initialize);
})();
