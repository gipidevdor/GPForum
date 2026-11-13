/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const source = document.currentScript;
  if (!source) return;
  const assets = source.dataset;
  const loaded = new Map();
  const modules = [
    ["formNavigation", "[data-account-menu], [data-navigation-filter], [data-transfer-form]"],
    ["composer", "form[data-composer]"],
    ["integrations", "[data-integration-embed]"],
    ["adminSettings", "[data-settings-search]"],
    ["similar", "[data-similar-threads]"],
    ["threadNavigation", "#posts .post[id]"],
    ["threadActions", "#posts .post[id]"],
    ["discussionWorkspace", ".thread #reply.composer"],
    ["editorSuggestions", "form[data-suggest-url]"],
    ["push", "[data-push-settings], [data-push-clear]"],
    ["passkeys", "form[data-passkey]"],
    ["notifications", "[data-notification-link]"],
    ["mathematics", ".math-expression"],
  ];
  const load = (name) => {
    if (loaded.has(name)) return loaded.get(name);
    const address = assets[name];
    if (!address) return Promise.resolve();
    let url;
    try { url = new URL(address, location.href); } catch { return Promise.resolve(); }
    if (url.origin !== location.origin || url.username || url.password) return Promise.resolve();
    const promise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = url.href;
      script.onload = resolve;
      script.onerror = () => { script.remove(); reject(new Error("enhancement unavailable")); };
      document.head.append(script);
    });
    loaded.set(name, promise);
    return promise;
  };
  const contains = (root, selector) => root.matches?.(selector) || root.querySelector?.(selector);
  const scan = (root) => {
    if (!root || (root.nodeType !== 1 && root !== document)) return;
    for (const [name, selector] of modules) {
      if (loaded.has(name) || !contains(root, selector)) continue;
      if (name === "mathematics") {
        if (document.documentElement.dataset.mathEnabled !== "1" || !assets.katex) continue;
        // Reserve the module while its dependency loads: concurrent fragments
        // share one library request and one initialization.
        const pending = load("katex").then(() => {
          loaded.delete(name);
          return load(name);
        });
        loaded.set(name, pending);
        pending.catch(() => {}); // Escaped source remains readable on failure.
      } else {
        load(name).catch(() => {}); // Native links and forms remain usable.
      }
    }
  };
  scan(document);
  // htmx 4 processes each inserted subtree, including out-of-band content.
  document.addEventListener("htmx:after:process", (event) => scan(event.target));
  new MutationObserver((changes) => {
    for (const change of changes) for (const node of change.addedNodes) scan(node);
  }).observe(document.body, {childList: true, subtree: true});
})();
