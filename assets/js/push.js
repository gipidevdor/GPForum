/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const italian = document.documentElement.lang.startsWith("it");
  const label = (en, it) => italian ? it : en;
  const initialized = new WeakSet();
  const refreshers = new WeakMap();
  const currentKey = "gpforum.push.subscription";
  let currentId = null;
  const saved = () => { try { return localStorage.getItem(currentKey) || currentId; } catch { return currentId; } };
  const remember = (id) => { currentId = id || null; try { id ? localStorage.setItem(currentKey, id) : localStorage.removeItem(currentKey); } catch {} };
  const supported = () => window.isSecureContext && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  const configuration = async () => {
    const response = await fetch("/push/configuration", {credentials: "same-origin", cache: "no-store", redirect: "error"});
    if (!response.ok) throw new Error("Push unavailable");
    return response.json();
  };
  const write = async (operation, input, config) => {
    const response = await fetch(`/push/${operation}`, {
      method: "POST", credentials: "same-origin", cache: "no-store", redirect: "error",
      body: new URLSearchParams({csrf_token: config.csrf_token, payload: JSON.stringify(input)}),
    });
    if (!response.ok) throw new Error("Push unavailable");
    return response.json();
  };
  const clear = async () => {
    if (!supported()) return;
    const registration = await navigator.serviceWorker.getRegistration("/push/");
    if (!registration) return;
    const subscription = await registration.pushManager.getSubscription();
    await subscription?.unsubscribe();
    for (const notification of await registration.getNotifications()) notification.close();
    remember(null);
  };
  const prepareWorker = async () => {
    const registration = await navigator.serviceWorker.register("/push-worker.js", {scope: "/push/", updateViaCache: "none"});
    const active = registration.active || registration.installing || registration.waiting;
    if (active && active.state !== "activated") await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("Worker unavailable")), 10000);
      active.addEventListener("statechange", () => {
        if (active.state === "activated") { clearTimeout(timeout); resolve(); }
        if (active.state === "redundant") { clearTimeout(timeout); reject(new Error("Worker unavailable")); }
      });
    });
    return registration;
  };
  const initialize = async (root) => {
    if (initialized.has(root)) return;
    initialized.add(root);
    const status = root.querySelector("[data-push-status]");
    if (!supported()) {
      status.textContent = label("Push is unavailable in this browser. On iPhone or iPad, add the forum to your Home Screen first.",
        "Push non disponibile in questo browser. Su iPhone o iPad aggiungi prima il forum alla schermata Home.");
      return;
    }
    const enable = root.querySelector("[data-push-enable]");
    const disable = root.querySelector("[data-push-disable]");
    let config;
    let registration;
    const refresh = async () => {
      config = await configuration();
      if (!config.enabled) { root.hidden = true; return; }
      registration ||= await prepareWorker();
      const device = config.devices.find((item) => item.subscription_id === saved());
      status.textContent = device?.active ? label("Active on this device", "Attive su questo dispositivo")
        : device ? label("Waiting for verification. Keep this page open.", "In attesa di verifica. Mantieni aperta questa pagina.")
        : label("Disabled on this device", "Disattivate su questo dispositivo");
      disable.disabled = !device;
      enable.disabled = false;
      for (const input of root.querySelectorAll("[data-push-kind]")) {
        input.checked = device ? device.kinds.includes(input.value) : true;
      }
    };
    enable.addEventListener("click", async () => {
      enable.disabled = true;
      try {
        const kinds = Array.from(root.querySelectorAll("[data-push-kind]:checked"), (input) => input.value);
        if (!kinds.length) throw new Error("Choose a notification kind");
        // Request permission directly from the user gesture, before network
        // or service worker registration can consume transient activation.
        const permission = await Notification.requestPermission();
        if (permission !== "granted") throw new Error("Permission not granted");
        if (!config.enabled) throw new Error("Push disabled");
        const key = Uint8Array.from(atob(config.application_server_key.replace(/-/g, "+").replace(/_/g, "/")), (ch) => ch.charCodeAt(0));
        let subscription = await registration.pushManager.getSubscription();
        if (subscription && subscription.options.applicationServerKey &&
          Array.from(new Uint8Array(subscription.options.applicationServerKey)).join() !== Array.from(key).join()) {
          await subscription.unsubscribe(); subscription = null;
        }
        subscription ||= await registration.pushManager.subscribe({userVisibleOnly: true, applicationServerKey: key});
        const result = await write("register", {...subscription.toJSON(), key_id: config.key_id, kinds}, config);
        remember(result.subscription_id);
        await refresh();
      } catch {
        status.textContent = label("Could not activate notifications. Check browser permission and try again.",
          "Attivazione non riuscita. Controlla il permesso del browser e riprova.");
      } finally { enable.disabled = false; }
    });
    disable.addEventListener("click", async () => {
      disable.disabled = true;
      try {
        config = await configuration();
        await write("revoke", {subscription_id: saved()}, config);
        await clear(); await refresh();
      } catch { status.textContent = label("Could not disable notifications. Try again.", "Disattivazione non riuscita. Riprova."); disable.disabled = false; }
    });
    refreshers.set(root, refresh);
    try { await refresh(); } catch { status.textContent = label("Push temporarily unavailable", "Push temporaneamente non disponibile"); }
  };
  const scan = () => {
    if (document.querySelector("[data-push-clear]")) clear().catch(() => {});
    document.querySelectorAll("[data-push-settings]").forEach((root) => initialize(root));
  };
  scan();
  if ("serviceWorker" in navigator) navigator.serviceWorker.addEventListener("message", (event) => {
    if (event.data?.type !== "gpforum.push.active" || event.source?.scriptURL !== new URL("/push-worker.js", location.origin).href) return;
    document.querySelectorAll("[data-push-settings]").forEach((root) => refreshers.get(root)?.().catch(() => {}));
  });
  document.addEventListener("htmx:afterSwap", scan);
})();
