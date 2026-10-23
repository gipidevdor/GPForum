/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const italian = document.documentElement.lang.startsWith("it");
  const label = (en, it) => italian ? it : en;
  const ready = new WeakSet();
  let serial = 0;
  const initialize = () => {
    document.querySelectorAll("form[data-suggest-url]").forEach(form => {
      const field = form.querySelector('textarea[name="body_source"]');
      if (!field || ready.has(field)) return;
      ready.add(field);
      const hint = document.createElement("p");
      hint.className = "ui-hint editor-suggestions-hint";
      hint.textContent = label("Type @ to mention a participant on this page, or [[ to find a discussion.",
        "Scrivi @ per citare un partecipante in pagina, oppure [[ per cercare una discussione.");
      const list = document.createElement("div");
      list.id = `editor-suggestions-${++serial}`;
      list.className = "editor-suggestions";
      list.setAttribute("role", "listbox");
      list.setAttribute("aria-label", label("Writing suggestions", "Suggerimenti di scrittura"));
      list.hidden = true;
      field.after(hint, list);
      field.setAttribute("aria-controls", list.id);
      field.setAttribute("aria-autocomplete", "list");
      let timer, request, sequence = 0, selected = -1, choices = [], token;
      const hide = () => {
        list.hidden = true;
        field.removeAttribute("aria-activedescendant");
        choices = [];
        selected = -1;
      };
      const activeToken = () => {
        if (field.selectionStart !== field.selectionEnd) return null;
        const end = field.selectionStart;
        const match = field.value.slice(Math.max(0, end - 200), end).match(/(?:^|[\s(])(@[\w.-]{1,64}|\[\[[^\]\n]{2,80})$/u);
        if (!match) return null;
        return { start: end - match[1].length, end, text: match[1] };
      };
      const choose = index => {
        const current = activeToken();
        if (!choices[index] || !current || !token || current.start !== token.start || current.text !== token.text) return;
        field.setRangeText(choices[index].insert, token.start, token.end, "end");
        hide();
        field.dispatchEvent(new Event("input", { bubbles: true }));
        field.focus({ preventScroll: true });
      };
      const show = items => {
        hide();
        if (!field.isConnected) return;
        choices = items.slice(0, 5);
        list.replaceChildren(...choices.map((item, index) => {
          const option = document.createElement("div");
          option.id = `${list.id}-${index}`;
          option.setAttribute("role", "option");
          option.setAttribute("aria-selected", "false");
          option.textContent = item.label;
          option.addEventListener("pointerdown", event => { event.preventDefault(); choose(index); });
          return option;
        }));
        list.hidden = choices.length === 0;
      };
      field.addEventListener("input", () => {
        clearTimeout(timer);
        request?.abort();
        const current = ++sequence;
        hide();
        token = activeToken();
        if (!token) return;
        if (token.text.startsWith("@")) {
          const prefix = token.text.slice(1).toLowerCase();
          const names = [...document.querySelectorAll("#posts .post__byline a[href]")].map(link => {
            try { return decodeURIComponent(new URL(link.href, document.baseURI).pathname.split("/u/")[1] || ""); }
            catch { return ""; }
          });
          show([...new Set(names)].filter(name => /^[a-z0-9_.-]{1,64}$/i.test(name) && name.toLowerCase().startsWith(prefix))
            .map(name => ({ label: `@${name}`, insert: `@${name} ` })));
          return;
        }
        const query = token.text.slice(2).trim();
        if (query.length < 3) return;
        timer = setTimeout(async () => {
          request = new AbortController();
          try {
            const url = new URL(form.dataset.suggestUrl, document.baseURI);
            url.searchParams.set("q", query);
            url.searchParams.set("limit", "5");
            const response = await fetch(url, { credentials: "same-origin", headers: { Accept: "application/json" }, signal: request.signal });
            if (!response.ok) return;
            const result = await response.json();
            if (current !== sequence || !field.isConnected || activeToken()?.text !== token?.text) return;
            show((Array.isArray(result.suggestions) ? result.suggestions : [])
              .filter(item => item.entity_type === "thread" && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(item.entity_id))
              .map(item => ({ label: String(item.title || ""), insert: `[${String(item.title || "").replace(/[\[\]\r\n]/g, " ")}](${form.dataset.threadBase.replace("THREAD_ID", item.entity_id)}) ` })));
          } catch { if (current === sequence) hide(); }
        }, 350);
      });
      field.addEventListener("keydown", event => {
        if (list.hidden || event.isComposing) return;
        if (event.key === "Escape") { event.preventDefault(); hide(); }
        else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          event.preventDefault();
          selected = selected < 0 ? (event.key === "ArrowDown" ? 0 : choices.length - 1)
            : (selected + (event.key === "ArrowDown" ? 1 : -1) + choices.length) % choices.length;
          [...list.children].forEach((option, index) => option.setAttribute("aria-selected", String(index === selected)));
          field.setAttribute("aria-activedescendant", list.children[selected].id);
        } else if (event.key === "Enter" && selected >= 0) { event.preventDefault(); choose(selected); }
      });
      field.addEventListener("blur", () => { clearTimeout(timer); request?.abort(); ++sequence; hide(); });
    });
  };
  initialize();
  document.addEventListener("htmx:afterSwap", initialize);
  document.addEventListener("htmx:oobAfterSwap", initialize);
})();
