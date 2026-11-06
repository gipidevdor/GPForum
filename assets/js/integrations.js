/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";

  const reveal = (root) => {
    if (!root) return;
    if (root.matches?.("button[data-integration-embed]")) root.hidden = false;
    root.querySelectorAll("button[data-integration-embed]").forEach((button) => {
      button.hidden = false;
    });
  };

  document.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-integration-embed]");
    if (!button) return;
    const card = button.closest(".integration-card");
    if (!card || !["audio", "video"].includes(button.dataset.embedKind)) return;
    let target;
    try { target = new URL(button.dataset.integrationEmbed); } catch { return; }
    if (target.protocol !== "https:" || target.username || target.password || target.port) return;
    if (target.origin !== button.dataset.embedOrigin) return;

    const frame = document.createElement("iframe");
    frame.className = button.dataset.embedKind === "audio" ? "integration-card__audio" : "integration-card__video";
    frame.title = button.dataset.embedTitle;
    frame.referrerPolicy = "strict-origin-when-cross-origin";
    frame.allow = "encrypted-media; fullscreen; picture-in-picture";
    frame.allowFullscreen = true;
    frame.src = button.dataset.integrationEmbed;
    button.replaceWith(frame);
    frame.focus();
  });

  reveal(document);
  for (const event of ["htmx:afterSwap", "htmx:oobAfterSwap"]) {
    document.addEventListener(event, (e) => reveal(e.detail?.target || e.target));
  }
  new MutationObserver((changes) => {
    for (const change of changes) {
      for (const node of change.addedNodes) {
        if (node.nodeType === 1) reveal(node);
      }
    }
  }).observe(document.body, { childList: true, subtree: true });
})();
