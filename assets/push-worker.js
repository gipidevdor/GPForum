/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
"use strict";
// This worker has no fetch handler and never caches application responses.
const italian = self.navigator.language?.startsWith("it");
const label = (en, it) => italian ? it : en;
const inbox = new URL("/notifications", self.location.origin).href;
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const activate = async (payload) => {
  if (!uuid.test(payload.subscription_id) || !/^[A-Za-z0-9_-]{43}$/.test(payload.nonce)) return;
  const configReply = await fetch("/push/configuration", {
    credentials: "same-origin", cache: "no-store", redirect: "error",
  });
  if (!configReply.ok) return;
  const config = await configReply.json();
  if (!config.enabled || typeof config.csrf_token !== "string") return;
  const response = await fetch("/push/confirm", {
    method: "POST", credentials: "same-origin", cache: "no-store", redirect: "error",
    body: new URLSearchParams({csrf_token: config.csrf_token, payload: JSON.stringify({
      subscription_id: payload.subscription_id, nonce: payload.nonce,
    })}),
  });
  if (!response.ok) return;
  const clients = await self.clients.matchAll({type: "window", includeUncontrolled: true});
  for (const client of clients) client.postMessage({type: "gpforum.push.active"});
};
self.addEventListener("push", (event) => {
  event.waitUntil((async () => {
    let payload;
    try {
      if (!event.data || event.data.arrayBuffer().byteLength > 1024) return;
      payload = event.data.json();
    } catch { return; }
    if (!payload || !["alert", "activation"].includes(payload.type)) return;
    await self.registration.showNotification("Good Phorum", {
      body: payload.type === "activation"
        ? label("Notification verification", "Verifica delle notifiche")
        : label("You have new notifications", "Hai nuove notifiche"),
      tag: payload.type === "activation" ? "gpforum-activation" : "gpforum-inbox",
      renotify: false, data: {type: payload.type},
    });
    if (payload.type === "activation") await activate(payload).catch(() => {});
  })());
});
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil((async () => {
    const clients = await self.clients.matchAll({type: "window", includeUncontrolled: true});
    for (const client of clients) {
      const url = new URL(client.url);
      if (url.origin === self.location.origin && url.pathname === "/notifications") return client.focus();
    }
    return self.clients.openWindow(inbox);
  })());
});
// Permission and subscription changes are reconciled on the settings page.
// No silent push, background authentication or automatic account rebind.
