/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";

  const composers = new WeakMap();
  const contentFields = ["kind", "category_id", "thread_id", "title", "body_source", "visibility"];
  const saveDelay = 900;
  const previewDelay = 350;

  const snapshot = (form) => {
    const fields = new URLSearchParams(new FormData(form));
    fields.delete("composer_action");
    return { fields, key: JSON.stringify(contentFields.map((name) => fields.get(name) || "")) };
  };

  const attached = (state) => state.form.isConnected;
  const message = (state, key, error = false) => {
    if (!attached(state)) return;
    state.status.textContent = state.tools.dataset[key] || "";
    state.status.classList.toggle("is-error", error);
  };

  const post = (url, fields, signal) => fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: { Accept: "application/json" },
    body: fields,
    signal,
  });

  const saveSnapshot = async (state, current) => {
    message(state, "saving");
    // Keep the complete request until acknowledged: a lost response must be
    // retried with the same revision and publish command, even after more typing.
    state.retry = current;
    try {
      const response = await post(state.tools.dataset.saveUrl, current.fields);
      const result = await response.json();
      if (!attached(state)) return;
      if (response.status === 409) {
        state.conflicted = true;
        state.retry = null;
        state.conflict.hidden = false;
        message(state, "conflict", true);
        throw new Error("draft conflict");
      }
      if (!response.ok || !result.ok || !result.draft) {
        // A definitive validation refusal is safe to replace with edited text.
        if (response.status >= 400 && response.status < 500) state.retry = null;
        throw new Error("draft refused");
      }
      const draft = result.draft;
      if (!Number.isInteger(Number(draft.draft_revision)) || Number(draft.draft_revision) < 1 || !draft.command_id) {
        throw new Error("invalid draft acknowledgement");
      }
      state.form.elements.namedItem("draft_revision").value = draft.draft_revision;
      state.form.elements.namedItem("command_id").value = draft.command_id;
      state.saved = current.key;
      state.retry = null;
      state.failed = false;
      message(state, "saved");
    } catch (error) {
      state.failed = true;
      if (!state.conflicted) message(state, "saveFailed", true);
      throw error;
    }
  };

  const flush = async (state, force = false) => {
    clearTimeout(state.saveTimer);
    if (state.conflicted) throw new Error("draft conflict");
    if (!attached(state)) throw new Error("composer replaced");
    if (state.pending) {
      await state.pending;
      return flush(state, force);
    }
    const current = state.retry || snapshot(state.form);
    if (!state.retry && !force && state.saved === current.key) return;
    state.pending = saveSnapshot(state, current);
    try {
      await state.pending;
    } finally {
      state.pending = null;
    }
    // Typing during an in-flight save is sent only after its revision is known.
    if (attached(state) && snapshot(state.form).key !== state.saved) return flush(state);
  };

  const preview = async (state) => {
    clearTimeout(state.previewTimer);
    const sequence = ++state.previewSequence;
    if (state.previewRequest) state.previewRequest.abort();
    state.previewRequest = new AbortController();
    const current = snapshot(state.form);
    state.preview.hidden = false;
    state.preview.setAttribute("aria-busy", "true");
    try {
      const response = await post(state.tools.dataset.previewUrl, current.fields, state.previewRequest.signal);
      const result = await response.json();
      if (!attached(state) || sequence !== state.previewSequence || current.key !== snapshot(state.form).key) return;
      if (!response.ok || !result.ok || typeof result.html !== "string") throw new Error("preview refused");
      // This HTML is produced by the same server renderer and render policy as posts.
      state.previewBody.innerHTML = result.html;
      state.previewStatus.textContent = "";
    } catch (error) {
      if (attached(state) && sequence === state.previewSequence && error.name !== "AbortError") {
        state.previewStatus.textContent = state.tools.dataset.previewFailed;
      }
    } finally {
      if (attached(state) && sequence === state.previewSequence) state.preview.removeAttribute("aria-busy");
    }
  };

  const initialize = () => {
    document.querySelectorAll("form[data-composer]").forEach((form) => {
      if (composers.has(form)) return;
      const tools = form.querySelector("[data-draft-tools]");
      const region = form.closest(".composer").querySelector("[data-composer-preview]");
      if (!tools || !region || !form.elements.namedItem("draft_id")) return;
      const state = {
        form, tools,
        status: tools.querySelector("[data-draft-status]"),
        conflict: tools.querySelector("[data-draft-conflict]"),
        preview: region,
        previewBody: region.querySelector("[data-preview-body]"),
        previewStatus: region.querySelector("[data-preview-status]"),
        saved: Number(form.elements.namedItem("draft_revision").value) > 0 ? snapshot(form).key : null,
        initial: snapshot(form).key,
        initialHasContent: ["title", "body_source"].some((name) => {
          const field = form.elements.namedItem(name);
          return field && field.value.length > 0;
        }),
        pending: null, retry: null, failed: false, conflicted: tools.dataset.conflicted === "true",
        previewSequence: 0, publishing: false, allowPublish: false,
      };
      composers.set(form, state);
      const changed = () => {
        // Invalidate earlier preview responses as soon as the input changes.
        ++state.previewSequence;
        clearTimeout(state.saveTimer);
        clearTimeout(state.previewTimer);
        if (!state.conflicted && !state.failed) {
          message(state, "unsaved");
          state.saveTimer = setTimeout(() => { flush(state).catch(() => {}); }, saveDelay);
        }
        state.previewTimer = setTimeout(() => { preview(state); }, previewDelay);
      };
      form.addEventListener("input", changed);
      form.addEventListener("change", changed);
      form.addEventListener("click", (event) => {
        const button = event.target.closest("button[name='composer_action']");
        if (!button || button.form !== form) return;
        // These controls have their own HTMX fallback. Handle their clicks
        // before HTMX so the enhanced composer uses JSON without a DOM swap.
        event.preventDefault();
        event.stopImmediatePropagation();
        if (button.value === "preview") preview(state);
        else flush(state, true).catch(() => {});
      }, true);
      form.addEventListener("submit", (event) => {
        const submitter = event.submitter;
        const action = submitter && submitter.name === "composer_action" ? submitter.value : "publish";
        if (action === "publish" && state.allowPublish) {
          state.allowPublish = false;
          return;
        }
        // Capture runs before HTMX's bubbling submit handler. The original
        // publish is replayed only after its exact content has a saved revision.
        event.preventDefault();
        event.stopImmediatePropagation();
        if (action === "preview") {
          preview(state);
        } else if (action === "save") {
          flush(state, true).catch(() => {});
        } else if (!state.publishing) {
          state.publishing = true;
          flush(state).then(() => {
            if (!attached(state)) return;
            state.allowPublish = true;
            if (submitter) form.requestSubmit(submitter);
            else form.requestSubmit();
          }).catch(() => {}).finally(() => { state.publishing = false; });
        }
      }, true);
    });
  };

  // Formatting uses the same input event as typing, including draft persistence.
  const initializeFormatting = () => {
    const italian = document.documentElement.lang.startsWith("it");
    document.querySelectorAll('form[data-composer] textarea[name="body_source"]').forEach((field) => {
      if (field.dataset.formattingReady) return;
      field.dataset.formattingReady = "true";
      const bar = document.createElement("div");
      bar.className = "composer-formatting";
      bar.setAttribute("role", "group");
      bar.setAttribute("aria-label", italian ? "Formattazione del testo" : "Text formatting");
      const actions = [
        [italian ? "Grassetto" : "Bold", "**", "**"],
        [italian ? "Corsivo" : "Italic", "*", "*"],
        [italian ? "Codice" : "Code", "`", "`"],
        [italian ? "Citazione" : "Quote", "\n> ", "\n"],
        [italian ? "Blocco di codice" : "Code block", "\n```\n", "\n```\n"],
        [italian ? "Elenco puntato" : "Bulleted list", "\n- ", "\n"],
        [italian ? "Elenco numerato" : "Numbered list", "\n1. ", "\n"],
      ];
      actions.forEach(([label, before, after]) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "button--quiet";
        button.textContent = label;
        button.addEventListener("click", () => {
          const start = field.selectionStart;
          const end = field.selectionEnd;
          const selected = field.value.slice(start, end);
          let content = selected;
          if (before === "\n> ") content = selected.replace(/\n/g, "\n> ");
          if (before === "\n- ") content = selected.replace(/\n/g, "\n- ");
          if (before === "\n1. ") content = selected.split("\n").map((line, index) =>
            index ? `${index + 1}. ${line}` : line).join("\n");
          field.setRangeText(before + content + after, start, end, "select");
          field.focus();
          field.setSelectionRange(start + before.length, start + before.length + content.length);
          field.dispatchEvent(new Event("input", { bubbles: true }));
        });
        bar.append(button);
      });
      field.before(bar);
      const count = document.createElement("output");
      count.className = "ui-hint";
      const updateCount = () => {
        const characters = Array.from(field.value).length;
        const words = field.value.trim() ? field.value.trim().split(/\s+/u).length : 0;
        count.textContent = italian ? `${characters} caratteri · ${words} parole` : `${characters} characters · ${words} words`;
      };
      field.after(count);
      field.addEventListener("input", updateCount);
      updateCount();
      field.addEventListener("keydown", (event) => {
        if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
        const index = { b: 0, i: 1 }[event.key.toLowerCase()];
        if (index === undefined) return;
        event.preventDefault();
        bar.children[index].click();
      });
    });
  };
  initializeFormatting();
  document.addEventListener("htmx:afterSwap", initializeFormatting);
  document.addEventListener("htmx:oobAfterSwap", initializeFormatting);

  initialize();
  document.addEventListener("htmx:afterSwap", initialize);
  document.addEventListener("htmx:oobAfterSwap", initialize);
  window.addEventListener("beforeunload", (event) => {
    const unsaved = [...document.querySelectorAll("form[data-composer]")].some((form) => {
      const state = composers.get(form);
      if (!state || !attached(state)) return false;
      const current = snapshot(form).key;
      const dirty = state.saved === null
        ? state.initialHasContent || current !== state.initial
        : current !== state.saved;
      return dirty || state.pending || state.retry;
    });
    if (unsaved) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
})();
