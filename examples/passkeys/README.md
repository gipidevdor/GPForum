# Good Phorum — registrazione passkey

Esempio eseguibile con Perl 5.40+, Mojolicious, Authen::WebAuthn 0.005 e
JavaScript nativo. Implementa i due endpoint JSON di registrazione, senza
salvataggio della credenziale o login.

La [guida passo-passo](../../docs/passkeys-registration.md) contiene avvio,
codice, prove e collegamento all'architettura GPForum. La prima pagina crea
un'identità dimostrativa temporanea, separata dagli account del forum.

Usare il demone a processo singolo; il registro temporaneo delle challenge
vive in memoria. Le dipendenze e il loro snapshot sono locali all'esempio.
