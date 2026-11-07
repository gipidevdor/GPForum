/* SPDX-FileCopyrightText: 2026 GPForum Contributors
 * SPDX-License-Identifier: BSD-3-Clause */

export class PasskeyError extends Error {
  constructor(message, code, cause) {
    super(message, { cause });
    this.name = "PasskeyError";
    this.code = code;
  }
}

export function toBase64URL(buffer) {
  const bytes = ArrayBuffer.isView(buffer)
    ? new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength)
    : new Uint8Array(buffer);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function fromBase64URL(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) {
    throw new PasskeyError("Codifica della challenge non valida.", "invalid_options");
  }
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(base64 + "=".repeat((4 - base64.length % 4) % 4));
  const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  if (toBase64URL(bytes) !== value) {
    throw new PasskeyError("Codifica della challenge non canonica.", "invalid_options");
  }
  return bytes;
}

export function creationOptions(publicKey) {
  return {
    ...publicKey,
    challenge: fromBase64URL(publicKey.challenge),
    user: { ...publicKey.user, id: fromBase64URL(publicKey.user.id) },
    excludeCredentials: (publicKey.excludeCredentials ?? []).map((entry) => ({
      ...entry, id: fromBase64URL(entry.id),
    })),
  };
}

export function registrationResponse(credential) {
  if (!credential || credential.type !== "public-key") {
    throw new PasskeyError("Il dispositivo non ha creato una passkey.", "not_created");
  }
  return {
    id: toBase64URL(credential.rawId),
    rawId: toBase64URL(credential.rawId),
    type: credential.type,
    response: {
      clientDataJSON: toBase64URL(credential.response.clientDataJSON),
      attestationObject: toBase64URL(credential.response.attestationObject),
    },
  };
}

async function postJSON(path, body, csrfToken, signal) {
  const response = await fetch(path, {
    method: "POST", credentials: "same-origin", cache: "no-store", redirect: "error",
    headers: {
      "Accept": "application/json", "Content-Type": "application/json",
      "X-CSRF-Token": csrfToken,
    },
    body: JSON.stringify(body), signal,
  });
  let result;
  try {
    result = await response.json();
  } catch (cause) {
    throw new PasskeyError("Il server ha restituito una risposta non valida.", "invalid_response", cause);
  }
  if (!response.ok) {
    const expired = result?.error === "challenge_expired_or_used";
    throw new PasskeyError(
      expired ? "La richiesta è scaduta o è già stata usata. Avvia una nuova registrazione."
        : "Il server ha rifiutato la registrazione. Avvia una nuova richiesta.",
      result?.error ?? "server_error",
    );
  }
  return result;
}

export async function registerPasskey({ csrfToken, signal } = {}) {
  try {
    if (!globalThis.isSecureContext || !globalThis.PublicKeyCredential || !navigator.credentials?.create) {
      throw new PasskeyError("WebAuthn richiede un browser compatibile e HTTPS (oppure localhost).", "unsupported");
    }
    if (!csrfToken) throw new PasskeyError("Ricarica la pagina per ottenere una sessione valida.", "csrf_missing");
    const options = await postJSON("/api/passkey/register/challenge", {}, csrfToken, signal);
    const credential = await navigator.credentials.create({
      publicKey: creationOptions(options.publicKey), signal,
    });
    const result = await postJSON(
      "/api/passkey/register/verify", registrationResponse(credential), csrfToken, signal,
    );
    if (result?.verified !== true) {
      throw new PasskeyError("La verifica non è stata confermata dal server.", "invalid_response");
    }
    return result;
  } catch (cause) {
    if (cause instanceof PasskeyError) throw cause;
    const messages = {
      NotAllowedError: "Operazione annullata, scaduta o non autorizzata dal dispositivo.",
      AbortError: "Registrazione annullata.",
      InvalidStateError: "La credenziale risulta già presente sul dispositivo.",
      SecurityError: "L'origine del sito o il dominio della passkey non sono validi.",
      NotSupportedError: "Il dispositivo non supporta le opzioni richieste.",
    };
    throw new PasskeyError(messages[cause?.name] ?? "Impossibile completare la registrazione. Riprova con una nuova richiesta.", cause?.name ?? "registration_failed", cause);
  }
}
