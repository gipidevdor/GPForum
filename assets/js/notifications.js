/* SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const link = document.querySelector("[data-notification-link]");
  if (!link) return;
  const badge = link.querySelector("[data-notification-count]");
  if (!badge) return;
  const updates = document.querySelector("[data-notification-update]");
  const pageCount = link.dataset.initialCount === undefined ? null : Number(link.dataset.initialCount);
  const interval = 60000;
  const channel = link.dataset.realtimeChannel;
  const recipient = channel?.startsWith("notifications:") ? channel.slice(14) : null;
  let checked = 0;
  let pending = false;
  let timer;
  let stopped = false;
  let paused = false;
  let socket = null;
  let live = false;
  let retryTimer = null;
  let handshakeTimer;
  let attempts = 0;
  let revision = 0;
  let realtimeDisabled = !link.dataset.realtimeUrl || !recipient || typeof window.WebSocket !== "function";
  const validCount = (count) => Number.isSafeInteger(count) && count >= 0;
  const display = (count) => {
    if (updates && pageCount !== null && count !== pageCount) updates.hidden = false;
    badge.hidden = count === 0;
    badge.textContent = count > 99 ? "99+" : String(count);
    link.setAttribute("aria-label", count > 0
      ? `${link.dataset.notificationLabel}: ${count > 99 ? "99+" : count}`
      : link.dataset.notificationLabel);
  };
  const disconnect = () => {
    const old = socket;
    socket = null;
    live = false;
    clearTimeout(handshakeTimer);
    if (old) old.close();
  };
  const schedule = () => {
    clearTimeout(timer);
    if (!document.hidden && !stopped && !paused && !live) timer = setTimeout(refresh, interval);
  };
  const refresh = async () => {
    if (document.hidden || stopped || paused || live || pending) return;
    if (Date.now() - checked < interval) { schedule(); return; }
    pending = true;
    checked = Date.now();
    const requestedRevision = revision;
    try {
      const response = await fetch(link.dataset.summaryUrl, {
        headers: { Accept: "application/json" }, credentials: "same-origin", cache: "no-store",
      });
      if (response.status === 401 || response.status === 403) {
        stopped = true;
        clearTimeout(retryTimer);
        disconnect();
        badge.hidden = true;
        link.setAttribute("aria-label", link.dataset.notificationLabel);
        return;
      }
      if (!response.ok) return;
      const result = await response.json();
      // A fallback begun before a push must not overwrite its newer count.
      if (requestedRevision === revision && !stopped && validCount(result.unread_count)) display(result.unread_count);
    } catch { /* Preserve the last count while the transport is unavailable. */ }
    finally { pending = false; schedule(); }
  };
  const failed = (candidate) => {
    if (socket !== candidate) return;
    disconnect();
    if (stopped || paused || document.hidden) return;
    refresh();
    if (!realtimeDisabled) {
      const delay = Math.min(60000, 1000 * 2 ** Math.min(attempts++, 6) * (1 + Math.random() * .25));
      clearTimeout(retryTimer);
      retryTimer = setTimeout(connect, delay);
    }
  };
  const connect = () => {
    if (stopped || paused || document.hidden || socket || realtimeDisabled) return;
    clearTimeout(retryTimer);
    retryTimer = null;
    let candidate;
    try {
      const url = new URL(link.dataset.realtimeUrl, window.location.href);
      if (url.origin !== window.location.origin || !["http:", "https:"].includes(url.protocol)) {
        realtimeDisabled = true;
        refresh();
        return;
      }
      url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
      candidate = new window.WebSocket(url.href);
      socket = candidate;
    } catch {
      realtimeDisabled = true;
      refresh();
      return;
    }
    // A transport that opens but never acknowledges/sends its snapshot is
    // also unavailable; it must not silence the fallback indefinitely.
    handshakeTimer = setTimeout(() => failed(candidate), 10000);
    let subscribed = false;
    let requested = false;
    candidate.addEventListener("message", (event) => {
      if (socket !== candidate || stopped || paused || document.hidden) return;
      let message;
      try { message = JSON.parse(event.data); } catch { return; }
      if (!message || typeof message !== "object") return;
      if (message.type === "realtime.connected" && !requested) {
        requested = true;
        try { candidate.send(JSON.stringify({ type: "subscribe", channel })); }
        catch { failed(candidate); }
      } else if (message.type === "subscribed" && message.channel === channel) {
        subscribed = true;
      } else if (message.type === "notification.badge" && subscribed && message.aggregate_id === recipient && validCount(message.payload?.unread_count)) {
        live = true;
        attempts = 0;
        revision++;
        checked = Date.now();
        clearTimeout(handshakeTimer);
        clearTimeout(timer);
        display(message.payload.unread_count);
      } else if (message.type === "error") {
        if (["authentication_required", "wrong_recipient", "forbidden", "unknown_channel", "malformed_channel"].includes(message.reason)) realtimeDisabled = true;
        failed(candidate);
      }
    });
    candidate.addEventListener("error", () => failed(candidate));
    candidate.addEventListener("close", (event) => {
      if (socket !== candidate) return;
      if (event.code === 1008) {
        stopped = true;
        clearTimeout(timer);
        clearTimeout(retryTimer);
        disconnect();
        badge.hidden = true;
        link.setAttribute("aria-label", link.dataset.notificationLabel);
        return;
      }
      failed(candidate);
    });
  };
  const activate = () => {
    if (document.hidden || stopped || paused) return;
    if (realtimeDisabled) refresh();
    else if (!retryTimer) connect();
  };
  const suspend = () => {
    clearTimeout(timer);
    clearTimeout(retryTimer);
    retryTimer = null;
    disconnect();
  };
  if (link.dataset.initialCount !== undefined) {
    const count = Number(link.dataset.initialCount);
    if (validCount(count)) { display(count); checked = Date.now(); }
  }
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) suspend();
    else activate();
  });
  window.addEventListener("focus", activate);
  window.addEventListener("pagehide", () => { paused = true; suspend(); });
  window.addEventListener("pageshow", () => { paused = false; activate(); });
  window.addEventListener("online", () => { clearTimeout(retryTimer); retryTimer = null; activate(); });
  activate();
})();
