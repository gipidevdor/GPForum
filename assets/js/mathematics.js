/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const selector = ".math-expression:not([data-math-state])";
  const render = (root) => {
    if (!globalThis.katex) return;
    const expressions = [...root.querySelectorAll(selector)];
    if (root.matches?.(selector)) expressions.unshift(root);
    expressions.forEach((element) => {
      const source = element.textContent;
      element.dataset.mathState = "ready";
      try {
        globalThis.katex.render(source, element, {
          displayMode: element.dataset.mathDisplay === "block",
          output: "mathml", trust: false, strict: "error", throwOnError: true,
          maxExpand: 1000, maxSize: 20, macros: {}, globalGroup: false,
        });
      } catch {
        element.dataset.mathState = "error";
        // A failed renderer may have replaced children before throwing.
        const code = document.createElement("code");
        code.textContent = source;
        element.replaceChildren(code);
        element.title = document.documentElement.lang.startsWith("it")
          ? "Formula non valida o non supportata: controlla il codice LaTeX."
          : "Invalid or unsupported equation: check the LaTeX source.";
      }
    });
  };
  render(document);
  const observer = new MutationObserver((changes) => {
    for (const change of changes) {
      for (const node of change.addedNodes) {
        if (node.nodeType === 1) render(node);
      }
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
})();
