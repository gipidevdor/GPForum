# Revisione Perl · sesta iterazione · 6 novembre 2026

Questa iterazione ottimizza il riepilogo dei post non letti e il riuso dei corpi già renderizzati, mantenendo gli stessi risultati. La base è il commit [40064b8f](https://github.com/gipidevdor/GPForum/commit/40064b8f2b2646b63b9353ce81f7a8b7b4bf1ed3), che comprende le cinque revisioni precedenti e Web Push/passkey. Le modifiche concorrenti ancora in lavorazione nel checkout condiviso sono escluse dalle copie verificate.

## Modifiche

- **Riepilogo dei non letti:** una sola scansione individua il primo post non letto nell’ordine della pagina, conta i non letti e trova la posizione massima visibile. Evita la seconda lettura di ogni posizione e l’array temporaneo dei post non letti. Per gli anonimi rimane la scansione già unica. Restano invariati i valori 0/undef, i risultati per pagine vuote e la distinzione fra ordine della pagina e posizione massima.
- **Corpi già renderizzati:** il renderer legge una sola volta il riferimento ai plugin; costruisce lo stato matematico mutabile solo dopo un miss. Gli hit riusano lo stesso HTML senza allocare il budget delle formule. Ogni nuovo corpo mantiene il proprio limite di 50 formule; cambiando il plugin seleziona ancora la variante corretta della memo.
- **Parità:** non cambiano SQL, autorizzazione, quote, TTL o dimensioni delle cache. I nuovi casi passano anche sul codice precedente: sono verifiche di equivalenza delle ottimizzazioni, senza un difetto funzionale dichiarato come corretto.

## Verifiche

La [suite generale finale](runs/unit-final/run.log) passa **698 file / 20.876 controlli**. Le [integrazioni PostgreSQL/HTTP](runs/integration-final/run.log) passano **4 file / 1.306 controlli**: letture aggregate della pagina del thread, parità fra Function API e ORM, riuso del lavoro e HTTP completo. [Perl::Critic](runs/critic-final/run.log), [sintassi, perltidy, runtime e architettura](runs/static-final/run.log) passano sui quattro file modificati. Nessuna baseline o policy è stata allargata. Il [controllo finale della documentazione](runs/documentation-final/run.log) passa sei controlli.

I [casi di parità sul codice precedente](runs/baseline-parity/run.log) passano. Coprono pagine vuote, tutte lette, parzialmente lette, ordine inverso, ID assenti, righe hash/ResultRow e riepiloghi anonimi. Le prove matematiche verificano budget separati, hit ripetuti e cambio del plugin sullo stesso renderer. Il primo [controllo di stile](runs/critic-initial/run.log) ha segnalato un indice numerico senza nome nei test, poi sostituito da una costante descrittiva. Il [primo candidato mirato](runs/focused-initial/run.log) passava 286 controlli; la suite generale finale copre anche l’ultima semplificazione del riferimento ai plugin.

## Misure finali

Le misure iniziano dopo correzioni e controlli. Micro e HTTP isolano entrambi **quinta → sesta iterazione**. Il confronto CPU è completo in ordine ABBA: prima A, dopo A, dopo B, prima B. Il confronto HTTP principale contiene soltanto la coppia iniziale A–B pulita: due campioni per configurazione e versione. Il secondo braccio candidato resta come replica descrittiva, fuori dalle statistiche principali. I manifesti verificano 957 percorsi applicativi all’inizio e alla fine; cambiano soltanto i due moduli dichiarati. Versioni, dataset e hash dell’harness HTTP coincidono nei bracci accettati. Nei campioni accettati non è stato rilevato altro carico riconosciuto di test, benchmark o compilazione.

L’ultimo braccio HTTP iniziale si è sovrapposto a un test esterno dei gestori dei servizi Unix. Quel campione è escluso dalle statistiche e conservato in [excluded-before-b-http-competing-test](runs/excluded-before-b-http-competing-test). Un secondo tentativo ha incrociato formattazione e test esterni, anch’essi conservati in [excluded-before-b-http-competing-tools](runs/excluded-before-b-http-competing-tools). Il tentativo dopo la finestra di quiete [registrata](runs/quiescence.json) ha ancora incrociato lavoro esterno ed è conservato in [excluded-before-b-http-after-quiescence](runs/excluded-before-b-http-after-quiescence). Il ritorno HTTP alla base è quindi escluso: resta soltanto il confronto iniziale A–B. Sono rimasti invariati gli altri campioni e tutti i controlli sui carichi; [campaign-event.json](runs/campaign-event.json) registra il rilievo e la decisione.

### Costo CPU del Perl

Tre lotti dopo 100 riscaldamenti, sei campioni per versione. Il lookup del read state usa lo stesso resultset in memoria; i post sono hash o veri ResultRow. Il rendering usa i veri plugin matematici e controlla l’output. I casi cold generano una sorgente distinta per chiamata e comprendono quel costo comune. Le pagine da 25 post rappresentano il caso ordinario di questo test; 200 righe sono un caso di scala della funzione, non una misura HTTP.

| Caso | Prima µs/op | Dopo µs/op | Variazione op/s | Fasce sovrapposte |
|---|---:|---:|---:|:---:|
| body_cold_math | 63.506 | 63.327 | +0.28% | sì |
| body_cold_plain | 25.371 | 25.439 | -0.27% | sì |
| body_hit_disabled_registry | 1.074 | 0.964 | +11.50% | no |
| body_hit_math | 1.960 | 1.352 | +44.99% | no |
| body_hit_plain | 0.630 | 0.633 | -0.45% | sì |
| summary_anonymous_25 | 20.531 | 20.606 | -0.36% | sì |
| summary_empty_member | 17.962 | 17.467 | +2.84% | no |
| summary_hash_25 | 43.904 | 32.424 | +35.41% | no |
| summary_result_rows_200 | 321.461 | 182.213 | +76.42% | no |
| summary_result_rows_25 | 58.010 | 40.008 | +45.00% | no |

### HTTP con PostgreSQL reale

Quattro worker; thread autenticato e home a concorrenza 1 e 32, thread guest a concorrenza 1; due ripetizioni per braccio e sei secondi nelle celle sotto carico. Il thread guest esercita la page cache, non il rendering di ciascun corpo su ogni richiesta. Quote, controlli di accesso e configurazione dell’harness sono identici fra i due rami.

**20 celle, 24,640 richieste, 0 risposte non valide**, nel confronto iniziale A–B, nessuna cella fallita o saltata. La replica separata del candidato contiene altre 10 celle e 12,212 richieste, con zero risposte non valide. Telemetria di tutti e quattro i worker presente in ciascun braccio.

| Path | Concorrenza | Prima req/s | Dopo req/s | Variazione | Fasce sovrapposte |
|---|---:|---:|---:|---:|:---:|
| guest.thread | 1 | 339.45 | 402.12 | +18.46% | sì |
| member.home | 1 | 161.32 | 160.46 | -0.53% | sì |
| member.home | 32 | 653.47 | 649.41 | -0.62% | no |
| member.thread | 1 | 81.51 | 80.53 | -1.20% | sì |
| member.thread | 32 | 342.45 | 329.21 | -3.87% | no |

| Path | Concorrenza | p95 prima → dopo ms | p99 prima → dopo ms | Fasce p95 / p99 sovrapposte |
|---|---:|---:|---:|:---:|
| guest.thread | 1 | 2.448 → 2.308 | 3.142 → 2.738 | sì / sì |
| member.home | 1 | 6.499 → 6.457 | 6.694 → 6.930 | sì / sì |
| member.home | 32 | 60.029 → 60.927 | 83.548 → 82.160 | sì / sì |
| member.thread | 1 | 12.742 → 13.466 | 12.753 → 13.555 | sì / no |
| member.thread | 32 | 106.679 → 118.679 | 138.965 → 186.081 | no / no |

Il primo confronto del thread autenticato a concorrenza 32 peggiora: **342,45 → 329,21 req/s (−3,87%)**, p95 **106,68 → 118,68 ms**, p99 **138,97 → 186,08 ms**. La replica candidata indipendente torna vicino alla base: **342,07 req/s**, p95 **105,76 ms**, p99 **134,11 ms**. Il peggioramento del primo passaggio non si ripete in questa replica; mancando il ritorno pulito alla base, non è possibile attribuire al codice né un guadagno globale né una regressione stabile.

Replica candidata descrittiva, esclusa dal confronto principale:

| Path | Concorrenza | req/s | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| guest.thread | 1 | 333.60 | 2.522 | 2.836 |
| member.home | 1 | 159.85 | 6.535 | 6.628 |
| member.home | 32 | 638.42 | 61.359 | 69.613 |
| member.thread | 1 | 80.51 | 13.713 | 14.111 |
| member.thread | 32 | 342.07 | 105.755 | 134.117 |

Minimi e massimi osservati non sono intervalli di confidenza. Le misure CPU non sono richieste HTTP al secondo. Il ritorno alla base HTTP è incompleto: la coppia A–B non conferma un miglioramento indipendente dall’ordine o globale. Il confronto breve non stabilisce capacità sostenuta o superiorità rispetto ad altri forum; CPU/RSS del generatore e del server condividono la macchina, e i campioni di utilizzo sono indicativi. Tutti i valori, compresi eventuali peggioramenti e sovrapposizioni, sono conservati in [summary.json](summary.json) e nei [dati grezzi](runs).

## Riproduzione ed evidenza

[bench.pl](bench.pl) è il microbenchmark Perl. Le snapshot locali effimere e i manifesti sono in [source-manifest.json](source-manifest.json). [application.patch](application.patch), [verification.patch](verification.patch) e le copie dei sorgenti fissano le modifiche. I test estesi compaiono nella copia di base solo per il confronto di parità; la patch dei test usa come base il commit originale. `SHA256SUMS` copre ogni artefatto, inclusi i primi tentativi di verifica.
