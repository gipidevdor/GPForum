# Revisione Perl · quinta iterazione · 6 novembre 2026

Questa revisione parte dal candidato verificato della [quarta iterazione](../2026-11-06-iteration-4/README.md). Corregge la coerenza della cache durante errori di lettura e calcoli annidati; riduce la sincronizzazione ripetuta dei canali PostgreSQL. Il codice applicativo cambia in due moduli; un terzo file aggiorna solo un commento. Le funzionalità indipendenti Web Push e passkey in lavorazione nel checkout condiviso sono escluse dalle copie verificate.

## Correzioni

- **Errori nelle notifiche:** il risultato del secondo tentativo di `pg_notifies` viene verificato. Un socket ancora illeggibile risponde `available => 0`; una lettura fallita ritira lo stato LISTEN di tutti i canali e conserva un gap per ciascun consumatore, anche se il recupero restituisce lo stesso handle. Il bus svuota L1 quando non può più garantirne la coerenza. Ogni chiamata conserva un solo tentativo di recupero.
- **Sincronizzazione dei canali:** ogni poll controlla ancora identità e PID del backend e legge le notifiche. Se la connessione e le registrazioni sono già correnti, evita di ordinare e riesaminare tutti i canali. Nuove registrazioni, cambio di handle/PID, LISTEN fallite e letture fallite riattivano la sincronizzazione. Le letture sane non aggiungono ping o SQL.
- **Calcoli durante un purge:** una sola epoca locale, senza mappe per chiave, accompagna i ticket della cache. Un purge locale o già assorbito da una lettura annidata ritira anche il risultato ancora in calcolo: `put` salta entrambe le scritture. La protezione vale con e senza GlifiStore, anche fra `serve_cached` e `render`. Il risultato calcolato resta restituibile alla richiesta corrente; il cambiamento impedisce di riutilizzarlo nelle richieste successive.
- **Compromesso esplicito:** l’epoca è comune alla cache. Un’invalidazione non correlata può scartare un riempimento valido e causare un miss aggiuntivo; lo stato resta costante invece di crescere con le chiavi invalidate. TTL, tag e formato dei token condivisi restano compatibili.

## Verifiche

La suite generale passa **693 file / 20.720 controlli**, i test mirati **8 file / 548 controlli** e le integrazioni reali **5 file / 605 controlli**. La [suite generale finale](runs/unit-canonical/run.log), i [test mirati](runs/focused-fixtures/run.log), le [integrazioni PostgreSQL/HTTP](runs/integration-final/run.log), [Perl::Critic](runs/critic-fixtures/run.log) e [sintassi, perltidy, runtime e architettura](runs/static-canonical/run.log) passano. La sintassi dei due ulteriori file di fixture è coperta dai test mirati e generali; Perl::Critic verifica tutti e dieci i file Perl. Le integrazioni esercitano una NOTIFY reale durante un calcolo, la disconnessione e la chiusura del backend, la revoca di pagine pubbliche e il rendering HTTP completo.

Gli [stessi casi di regressione sul codice precedente](runs/baseline-red-final/run.log) falliscono. Restano archiviati anche i primi tentativi: il primo comando mirato conteneva un nome di test inesistente; il controllo di stile ha richiesto perltidy sui test; tre fixture HTTP prive di database usavano erroneamente la cache con bus reale. Queste fixture ora ricevono una cache locale esplicita e mantengono tutte le asserzioni sugli hit. Gli errori delle fixture sono coperti dal primo passaggio mirato e dalla [prima suite generale](runs/unit-final/run.log). Nessuna baseline o policy architetturale è stata allargata. Il [controllo finale della documentazione](runs/documentation-canonical/run.log) passa sei controlli.

Il primo avvio delle misure è stato interrotto dal monitor per interrogazioni di localizzazione `xcodebuild -find git`. Mancando orari per singola cella, quel campione è stato escluso e la campagna ABBA è ripartita da zero. Il [rilievo originale e la correzione del filtro](runs/monitor-review.json) restano conservati insieme ai dati interrotti. Il filtro esclude soltanto questa interrogazione; gli altri controlli sui carichi restano attivi.

## Misure finali

Tutte le misure seguono le correzioni e i controlli. Entrambi i confronti isolano **quarta → quinta iterazione**. Ordine ABBA: prima A, dopo A, dopo B, prima B. Stesso hardware, runtime, dipendenze, dataset e harness. I manifesti controllano 973 percorsi applicativi all’inizio e alla fine; soltanto tre file differiscono, di cui uno nei commenti. Nessun altro carico riconosciuto di test, benchmark o compilazione è stato rilevato. Le fasce sotto sono minimi e massimi osservati, non intervalli di confidenza.

### Costo CPU del Perl

Tre lotti per braccio dopo 100 riscaldamenti, sei campioni per versione. Handle e client condiviso sono double in memoria identici: questi valori misurano lavoro Perl e non includono latenza SQL o di rete. Anche i poll vuoti leggono sempre `pg_notifies`. I riempimenti includono prima l’invalidazione e poi un nuovo valore valido, identico nei due rami.

| Caso | Prima µs/op | Dopo µs/op | Variazione op/s | Fasce sovrapposte |
|---|---:|---:|---:|:---:|
| idle_notify_1_channels | 8.554 | 8.006 | +6.84% | no |
| idle_notify_2_channels | 8.905 | 7.958 | +11.90% | no |
| idle_notify_8_channels | 11.277 | 7.970 | +41.49% | no |
| l1_hit_with_bus_two_channels | 16.816 | 15.987 | +5.19% | no |
| l1_hit_without_bus | 3.547 | 3.502 | +1.27% | sì |
| local_empty_tag_purge | 1.883 | 2.356 | -20.05% | no |
| local_invalidate_and_fill | 20.277 | 22.321 | -9.16% | no |
| shared_invalidate_and_fill | 63.596 | 69.519 | -8.52% | no |

### HTTP con PostgreSQL reale

Quattro worker; home e ricerca a concorrenza 1 e 32, categoria a concorrenza 1; due ripetizioni per braccio e sei secondi nelle celle sotto carico. Il normale bus della cache resta attivo; listener realtime in background e GlifiStore sono disabilitati dall’harness comune.

**40 celle, 50,474 richieste, 0 risposte non valide**, nessuna cella fallita o saltata. Telemetria di tutti e quattro i worker presente in ciascun braccio.

| Path | Concorrenza | Prima req/s | Dopo req/s | Variazione | Fasce sovrapposte |
|---|---:|---:|---:|---:|:---:|
| member.category | 1 | 143.38 | 142.83 | -0.38% | sì |
| member.home | 1 | 159.59 | 162.35 | +1.73% | sì |
| member.home | 32 | 662.51 | 675.28 | +1.93% | sì |
| member.search | 1 | 91.35 | 93.60 | +2.46% | sì |
| member.search | 32 | 344.50 | 346.02 | +0.44% | sì |

Le mediane HTTP variano dal **−0,38% al +2,46%**, con fasce sovrapposte in tutti i path: questo confronto non dimostra un aumento globale del throughput. I poll con uno e due canali migliorano invece del 6,84% e 11,90% nelle misure CPU isolate. Il purge di un tag vuoto costa 0,473 µs in più; invalidazione e riempimento locale passano da 20,277 a 22,321 µs e quello condiviso da 63,596 a 69,519 µs. Sono costi reali della protezione del risultato ancora in calcolo.

| Path | Concorrenza | p95 prima → dopo ms | p99 prima → dopo ms | Fasce p95 / p99 sovrapposte |
|---|---:|---:|---:|:---:|
| member.category | 1 | 7.093 → 7.141 | 7.510 → 7.496 | sì / sì |
| member.home | 1 | 6.397 → 6.496 | 6.718 → 7.039 | sì / sì |
| member.home | 32 | 58.625 → 52.702 | 78.065 → 67.028 | sì / sì |
| member.search | 1 | 11.718 → 11.104 | 12.213 → 11.492 | sì / sì |
| member.search | 32 | 96.186 → 96.010 | 111.499 → 107.290 | sì / sì |

La tabella completa di p50/p95/p99, CPU e RSS è in [summary.json](summary.json); i campioni grezzi sono in [runs](runs). Le misure brevi non dimostrano capacità sostenuta o superiorità rispetto ad altri forum. I costi dei riempimenti e delle invalidazioni sono conservati insieme ai miglioramenti dei poll: una correzione di coerenza non viene presentata come un guadagno su ogni percorso.

## Riproduzione ed evidenza

[bench.pl](bench.pl) è il microbenchmark Perl. [application.patch](application.patch), [verification.patch](verification.patch), le copie prima/dopo e [source-manifest.json](source-manifest.json) fissano il confronto. I test nuovi compaiono anche nella copia di base solo per riprodurre i casi rossi. `SHA256SUMS` copre tutti gli artefatti, inclusi i tentativi falliti. Le snapshot locali con dipendenze restano indicate nel manifesto; sono percorsi effimeri, non checkout pubblici.
