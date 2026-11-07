/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
(() => {
  "use strict";
  const from64 = (value) => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), ch => ch.charCodeAt(0));
  const to64 = (value) => btoa(String.fromCharCode(...new Uint8Array(value))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const initialized = new WeakSet();
  const supported = () => window.isSecureContext && !!window.PublicKeyCredential && !!navigator.credentials;
  const address = (value) => {
    const url = new URL(value, location.href);
    if (url.origin !== location.origin || url.username || url.password) throw new Error("address");
    return url.href;
  };
  const post = async (url, body, token, signal) => {
    const json = typeof body === "string";
    const response = await fetch(address(url), {method: "POST", credentials: "same-origin", cache: "no-store",
      redirect: "error", signal, headers: {Accept: "application/json", "X-CSRF-Token": token,
        ...(json ? {"Content-Type": "application/json"} : {})}, body});
    if (!response.ok) throw new Error("request");
    return response.json();
  };
  const initialize = () => {
    for (const form of document.querySelectorAll("form[data-passkey]")) {
      if (initialized.has(form)) continue;
      initialized.add(form);
      const status = form.querySelector("[data-passkey-status]");
      const button = form.querySelector('button[type="submit"]');
      const cancel = form.querySelector("[data-passkey-cancel]");
      if (!supported()) { status.textContent = form.dataset.unsupported; continue; }
      button.disabled = false;
      let controller;
      cancel?.addEventListener("click", () => controller?.abort());
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        if (controller) return;
        controller = new AbortController();
        const signal = controller.signal;
        button.disabled = true;
        if (cancel) cancel.hidden = false;
        status.textContent = form.dataset.waiting;
        try {
          const fields = new URLSearchParams(new FormData(form));
          const token = fields.get("csrf_token") || "";
          const {publicKey} = await post(form.action, fields, token, signal);
          publicKey.challenge = from64(publicKey.challenge);
          if (publicKey.user) publicKey.user.id = from64(publicKey.user.id);
          for (const key of publicKey.excludeCredentials || []) key.id = from64(key.id);
          const registering = form.dataset.passkey === "register";
          const credential = await navigator.credentials[registering ? "create" : "get"]({publicKey, signal});
          if (!credential) throw new Error("credential");
          const response = credential.response;
          const payload = {id: to64(credential.rawId), rawId: to64(credential.rawId), type: credential.type,
            response: {clientDataJSON: to64(response.clientDataJSON)}};
          if (registering) payload.response.attestationObject = to64(response.attestationObject);
          else Object.assign(payload.response, {authenticatorData: to64(response.authenticatorData),
            signature: to64(response.signature), userHandle: response.userHandle ? to64(response.userHandle) : null});
          const answer = await post(form.dataset.finish, JSON.stringify(payload), token, signal);
          if (!answer.next || !(answer.ok || answer.status === "second_factor")) throw new Error("result");
          location.assign(address(answer.next));
        } catch (error) {
          status.textContent = ["AbortError", "NotAllowedError"].includes(error.name)
            ? form.dataset.cancelled : form.dataset.failed;
        } finally {
          controller = null;
          button.disabled = false;
          if (cancel) cancel.hidden = true;
        }
      });
    }
  };
  initialize();
  document.addEventListener("htmx:after:swap", initialize);
})();
