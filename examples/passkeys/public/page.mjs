/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */
import { registerPasskey } from "./passkeys.mjs";

const button = document.querySelector("#register-passkey");
const cancel = document.querySelector("#cancel-passkey");
const status = document.querySelector("#passkey-status");
let active;
button.disabled = false;
cancel.addEventListener("click", () => active?.abort());
button.addEventListener("click", async () => {
  button.disabled = true;
  cancel.hidden = false;
  active = new AbortController();
  status.textContent = "Segui le istruzioni del dispositivo: biometria o PIN.";
  try {
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
    await registerPasskey({ csrfToken, signal: active.signal });
    status.textContent = "Verifica riuscita. In questo esempio la chiave non è salvata e non abilita l'accesso.";
  } catch (error) {
    status.textContent = error.message;
  } finally {
    active = undefined;
    button.disabled = false;
    cancel.hidden = true;
  }
});
