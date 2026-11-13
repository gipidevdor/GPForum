# Passkey nel forum e dimostrazione WebAuthn

## Funzionalità integrata

Le passkey del forum si gestiscono da **Menu → Passkey** oppure dalle
**Impostazioni di sicurezza**, all'indirizzo `/settings/passkeys`.
Il pulsante **Accedi con una passkey** è nella pagina di accesso. La
registrazione salva la chiave pubblica in PostgreSQL; il login verifica
una firma del dispositivo e apre una normale sessione del forum.

Per aggiungere o revocare una passkey servono la sessione corrente, la password
e, se attiva, la verifica TOTP o un codice di recupero. Il login mantiene il
secondo fattore configurato e gli obblighi di sicurezza dello staff. La revoca
disconnette gli altri dispositivi e invalida le verifiche TOTP pendenti.
La modifica e il recupero della password revocano tutte le passkey.

Installare le dipendenze principali con `script/bootstrap-deps --postgres`,
applicare `2043_passkeys.sql`, aggiornare i permessi del ruolo API e riavviare
l'applicazione dopo il deployment. `GPFORUM_PUBLIC_BASE_URL` deve corrispondere
esattamente all'indirizzo aperto nel browser: HTTPS sul dominio pubblico,
oppure HTTP su `localhost` per lo sviluppo. Aprire `http://localhost:3000`
anche quando il server ascolta su `127.0.0.1`, e configurare lo stesso URL pubblico. Dominio e origine
non vengono presi dagli header del client. Le passkey di un dominio non sono
disponibili su un altro. Servono JavaScript e un browser con WebAuthn.

Le challenge sono monouso, durano cinque minuti e sono condivise fra i worker
tramite PostgreSQL. Il forum supporta fino a dieci passkey attive per account,
chiavi ES256 con verifica dell'utente e credenziali sincronizzate.

```sh
script/gpforum-carton exec prove -l -It/lib --exec 'perl -Ilib -It/lib -MGPForum::Test::TemporaryPostgres' t/integration/postgres-passkeys.t
node --test t/js/forum-passkeys.test.cjs
```

Le prove eseguono il verificatore crittografico reale e i flussi HTTP;
la conferma fisica con Face ID, Touch ID, PIN o chiave hardware va provata
sul dispositivo.

## Esempio didattico separato

Questa guida implementa la **registrazione e verifica** richieste, con
`Authen::WebAuthn` 0.005, Mojolicious e JavaScript nativo. Il codice completo
è in [examples/passkeys](../examples/passkeys/README.md).

La risposta finale distingue esplicitamente `verified: true` da
`persisted: false`: la credenziale viene verificata, ma non è salvata e non
abilita il login. Questo comportamento riguarda soltanto l'esempio separato;
il percorso del forum descritto sopra salva le credenziali e abilita l'accesso.

## 1. Preparare ambiente e origine

Servono Perl 5.40+, Carton e un browser con WebAuthn. Le dipendenze dell'esempio
sono separate da quelle del servizio: [cpanfile](../examples/passkeys/cpanfile)
e [snapshot](../examples/passkeys/cpanfile.snapshot). Non modificare il lock
principale per provare questo percorso.

Dalla radice del repository, installare il lock dell'esempio:

```sh
cd examples/passkeys
../../script/gpforum-carton install --deployment
cd ../..
```

Su macOS, se il sistema seleziona OpenSSL 4 e la compilazione di Net::SSLeay
fallisce, usare OpenSSL 3 per questa installazione:

```sh
brew install openssl@3
cd examples/passkeys
OPENSSL_PREFIX="$(brew --prefix openssl@3)" ../../script/gpforum-carton install --deployment
cd ../..
```

Avviare il demone a processo singolo:

```sh
"$(script/gpforum-system-perl --require)" examples/passkeys/app.pl daemon -l http://127.0.0.1:3000
```

Aprire [http://localhost:3000](http://localhost:3000), con quel nome: RP ID, origine e URL del
browser devono essere coerenti. `localhost` beneficia dell'eccezione dei
browser per lo sviluppo locale; un dominio reale richiede HTTPS.

Per un'origine HTTPS di prova predisporre TLS, anche tramite il reverse proxy
come nella [guida di deployment](DEPLOYMENT.md), e configurare
`GPFORUM_PASSKEY_DEMO_ORIGIN`, per
esempio `https://forum.example.org`, senza percorso o slash finale. Il server
deriva l'RP ID da questa configurazione: `forum.example.org`, senza schema o
porta. Non lo ricava dagli header `Host` o `X-Forwarded-Host` ricevuti.

`GPFORUM_PASSKEY_DEMO_SECRET` può fissare un segreto casuale di almeno 32
caratteri. Senza questa variabile il segreto viene generato a ogni avvio e le
sessioni precedenti diventano invalide. Il demone rifiuta il prefork: il
registro delle challenge dell'esempio è intenzionalmente a processo singolo.

## 2. Separare controller, verifica e stato temporaneo

| File | Responsabilità |
| --- | --- |
| [App.pm](../examples/passkeys/lib/GPForum/Example/Passkeys/App.pm) | Configurazione fissa, sessioni, pagina, rotte |
| [Controller.pm](../examples/passkeys/lib/GPForum/Example/Passkeys/Controller.pm) | JSON, identità di sessione, Origin, CSRF e risposte HTTP |
| [Registration.pm](../examples/passkeys/lib/GPForum/Example/Passkeys/Registration.pm) | Opzioni WebAuthn, Base64URL, controlli strutturali e adattatore Authen::WebAuthn |
| [Challenges.pm](../examples/passkeys/lib/GPForum/Example/Passkeys/Challenges.pm) | Nonce casuali, scadenza e consumo sul server |
| [passkeys.mjs](../examples/passkeys/public/passkeys.mjs) | Fetch, conversioni binarie e API nativa del browser |
| [page.mjs](../examples/passkeys/public/page.mjs) | Pulsanti, annullamento e messaggi accessibili |

I namespace `GPForum::Example::Passkeys::*` appartengono all'esempio. Non sono
registrati nel bootstrap del servizio e non espongono rotte sull'applicazione
GPForum principale. La pagina assegna un identificatore casuale temporaneo
alla sessione dimostrativa; non autentica un account reale.

## Parte 1 — Server Perl / Mojolicious

### 3. Server: emettere la challenge

`POST /api/passkey/register/challenge` riceve `{}` con cookie e header
`X-CSRF-Token`. Il controller richiede l'origine esatta configurata e usa
`validation->csrf_protect` di Mojolicious, che gestisce anche il token
mascherato generato nella pagina.

Il server genera 32 byte con `Crypt::URandom`, li codifica Base64URL senza
padding e conserva nella sessione firmata:

```text
passkey_registration = { challenge, expires_at }
```

La risposta contiene `publicKey`, con:

- `challenge`: la challenge Base64URL;
- `rp`: `PublicKeyCredentialRpEntity`, con `id` configurato e nome Good Phorum;
- `user`: `PublicKeyCredentialUserEntity`, ricavata dalla sessione, con un ID
  opaco di 32 byte codificato Base64URL e nome visualizzabile;
- `pubKeyCredParams`: `public-key`, ES256 (`alg: -7`);
- `authenticatorSelection`: `platform`, `residentKey: required` e
  `userVerification: required`;
- `attestation: none`, timeout di 60 secondi e `excludeCredentials` vuoto.

La challenge scade dopo cinque minuti. Una nuova emissione invalida quella
precedente della stessa sessione. Il registro sul server è limitato e rimuove
le voci scadute.

**La sessione firmata non basta per impedire il replay.** Eliminare il campo
dal nuovo cookie non invalida una copia del cookie precedente. Per questo
`Challenges` conserva anche un nonce sul server e lo consuma una sola volta,
prima della verifica, senza operazioni asincrone intermedie. Al riavvio, il
registro viene perso e ogni challenge precedente viene rifiutata.

### 4. Server: verificare la registrazione

`POST /api/passkey/register/verify` riceve:

```text
{ id, rawId, type: "public-key",
  response: { clientDataJSON, attestationObject } }
```

Il controller ripete i controlli di sessione, Origin e CSRF e consuma la
challenge. Anche una risposta crittografica errata la consuma: occorre
iniziare una nuova registrazione.

L'adattatore limita dimensioni e profondità, verifica Base64URL canonico e
decodifica i campi ricevuti. Rifiuta cerimonie con `crossOrigin: true` o
`topOrigin`, attestazioni diverse da `none`, estensioni non richieste, ID
discordanti e algoritmi diversi dall'ES256 offerto. Verifica anche il punto
pubblico P-256 tramite CryptX.

Il CBOR esterno e il COSE incorporato vengono controllati con `new_safe`,
profondità limitata e tag rifiutati **prima** di essere passati al decoder
interno della libreria. I byte restano originali per la verifica WebAuthn.

La chiamata effettiva ad Authen::WebAuthn usa la sua API Base64URL:

```perl
$validator->validate_registration(
    challenge_b64             => $expected_challenge,
    requested_uv              => 'required',
    client_data_json_b64      => $response->{clientDataJSON},
    attestation_object_b64    => $response->{attestationObject},
    allowed_attestation_types => ['None'],
);
```

La libreria verifica tipo di cerimonia, challenge, origine, hash dell'RP ID,
presenza e verifica dell'utente, oltre all'attestazione selezionata. Il
blocco `eval` richiesto è confinato nell'adattatore: converte i `croak` CPAN
in una `Mojo::Exception` generica. I controller usano `try/catch` nativo di
Perl 5.40. Il valore di `$EVAL_ERROR`, che può contenere dati ricevuti e
challenge, non finisce nelle risposte o nei log.

In caso valido il servizio restituisce al controller ID della credenziale,
chiave pubblica COSE e contatore. Il punto in cui inserirli nello store è
marcato nel controller. L'esempio risponde:

```json
{"ok":true,"verified":true,"persisted":false}
```

Le risposte di errore sono JSON: 400 per dati invalidi, 401 senza sessione,
403 per Origin o CSRF, 409 per challenge scaduta/usata, 503 se il registro
temporaneo non può emettere un'altra challenge. Il corpo HTTP è limitato a
64 KiB; un superamento viene rifiutato da Mojolicious prima del controller.

### 5. Collegare il percorso agli account e a PostgreSQL

Per trasformare questa dimostrazione in una registrazione persistente nel
servizio GPForum:

1. Nel controller reale usare l'identità verificata da `current_user_id`,
   `identity_post_guard` e una riautenticazione recente, come per le altre
   modifiche alla sicurezza. Non accettare l'utente dal JSON né copiare
   l'identità dimostrativa dell'esempio.
2. Assegnare e conservare un `user_handle` casuale, stabile e opaco per
   ciascun account/RP. Usarlo per `user.id`; non usare email o nome utente.
3. Spostare emissione e consumo delle challenge in funzioni SQL versionate,
   attraverso `GPForum::Infrastructure::SqlFunction`. Il consumo deve essere
   atomico, con proprietario, scopo, RP e scadenza verificati sul server.
   Il registro in memoria non serve per worker o host multipli.
4. Salvare nella stessa transazione canonica utente, ID credenziale unico,
   chiave pubblica COSE, contatore iniziale e metadati necessari alle future
   assertion. Base64URL è il formato di trasporto: in PostgreSQL ID e COSE
   possono diventare `bytea`. Vincolo unico, audit e rifiuto di assegnazione
   della stessa credenziale a due account devono essere nello store.
5. Popolare `excludeCredentials` dalle credenziali già registrate e aggiungere
   elenco, revoca e limiti per account. Rispondere `persisted: true` soltanto
   dopo il commit. PostgreSQL rimane raggiunto tramite socket Unix.

Questi passaggi non sono eseguiti dalla dimostrazione. Nessuna migrazione,
credenziale reale o policy del secondo fattore viene modificata.

### 6. Distinguere registrazione e accesso

L'accesso richiederà un'altra cerimonia: challenge dedicata,
`navigator.credentials.get()`, ricerca della chiave salvata e
`validate_assertion()`, con gestione dei contatori e dello stato delle
credenziali sincronizzate. Le passkey sincronizzate possono avere contatore
zero: una regola universale di incremento non è sufficiente.

La documentazione di Authen::WebAuthn 0.005 riporta una cautela esplicita
sull'uso passwordless. Questa guida non qualifica quella versione come
implementazione completa WebAuthn Level 3 né abilita un accesso passwordless.
Prima di quel passaggio occorrono una verifica aggiornata del verificatore,
persistenza completa e prove dei flussi di assertion e recupero account.

## Parte 2 — Client JavaScript nativo

### 7. Client: chiedere la credenziale al dispositivo

La funzione esportata dal modulo si usa dopo un'azione esplicita dell'utente:

```js
import { registerPasskey } from "/passkeys.mjs";

const controller = new AbortController();
try {
  const result = await registerPasskey({
    csrfToken: document.querySelector('meta[name="csrf-token"]').content,
    signal: controller.signal,
  });
  // In questo esempio: result.verified === true, result.persisted === false.
} catch (error) {
  document.querySelector("#passkey-status").textContent = error.message;
}
// Per annullare l'operazione: controller.abort().
```

`registerPasskey()` chiama la challenge con `fetch`, cookie `same-origin`,
cache disabilitata e token CSRF. Converte `challenge`, `user.id` e gli eventuali
`excludeCredentials[].id` da Base64URL a `Uint8Array`, poi invoca:

```js
await navigator.credentials.create({ publicKey, signal });
```

Il browser sceglie l'interazione del dispositivo. Su dispositivi compatibili
può apparire Face ID o Touch ID; la verifica può anche usare il PIN. Il server
verifica il flag UV e non può stabilire quale metodo biometrico sia stato usato.
Le informazioni biometriche restano nel dispositivo.

Il codice serializza esplicitamente `rawId`, `clientDataJSON` e
`attestationObject` in Base64URL. Fare soltanto `JSON.stringify(credential)`
perderebbe i buffer necessari. La risposta viene inviata con un secondo POST;
annullamento, timeout, browser incompatibile, risposta HTTP errata e JSON
malformato producono errori gestiti. Nessuna verifica viene ritentata
automaticamente con la stessa challenge.

## 8. Verificare il codice

Dalla radice, dopo l'installazione delle dipendenze dell'esempio:

```sh
"$(script/gpforum-system-perl --require)" -S prove -lv examples/passkeys/t/registration.t
node --test t/js/passkeys.test.cjs
```

Il test Perl costruisce una vera chiave P-256 e una risposta CBOR `none`,
quindi chiama **Authen::WebAuthn reale**, senza simulare il verificatore.
Copre origine, RP, challenge, UP/UV, algoritmo, codifiche errate, replay con
vecchio cookie, scadenza e flag delle credenziali sincronizzate. I test JS
coprono conversioni binarie, opzioni della chiamata nativa, payload, CSRF,
annullamento ed errori HTTP.

Per provare l'interfaccia biometrica occorre il browser sul dispositivo:
aprire la pagina, premere il pulsante e completare la richiesta del sistema.
I test automatici non dimostrano l'esecuzione fisica di Face ID o Touch ID.
La creazione può lasciare una credenziale dimostrativa per `localhost` nel
gestore passkey del dispositivo; può essere rimossa dopo la prova.

## Riferimenti

- [Authen::WebAuthn 0.005: API e caveat](https://metacpan.org/release/MBESSON/Authen-WebAuthn-0.005/view/lib/Authen/WebAuthn.pod)
- [WebAuthn: registrazione di una credenziale](https://www.w3.org/TR/webauthn-3/#sctn-registering-a-new-credential)
- [Mojolicious: sessioni e controller](https://docs.mojolicious.org/Mojolicious/Controller#session)
- [Architettura di GPForum](../ARCHITECTURE.md)
- [Contratto del secondo fattore](adr/0142-two-step-sign-in-with-a-time-based-code.md)
