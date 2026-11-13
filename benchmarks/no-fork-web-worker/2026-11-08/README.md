# Worker web senza fork verso PostgreSQL · 8 novembre 2026

Confronto fra [bb8918e5](https://github.com/gipidevdor/GPForum/commit/bb8918e53e95bc797ac1c9c4b570768143c0187c) (prima) e [70a3f7e1](https://github.com/gipidevdor/GPForum/commit/70a3f7e16c65fe8dededb30b6076eb68162695ac) (dopo), il commit che toglie a `call_p` il ripiego sul processo figlio ([ADR 0176](../../../docs/adr/0176-a-web-worker-never-forks-to-reach-postgresql.md)). Lo schema del database è identico nelle due revisioni.

Misure locali su Apple M4 (10 core, 16 GiB), Perl 5.44.0, Mojolicious 9.54 e PostgreSQL 18.6, con `script/benchmark-http-complete`, due worker Hypnotoad e il dataset `PerformanceSeed` (103 utenti, 240 thread, 4.800 post). Generatore, server e database condividono la macchina, che eseguiva anche altre sessioni di lavoro. Nessuna cella ha registrato errori.

I dati completi sono in [summary.json](summary.json). [dashboard.html](dashboard.html) è la sorgente della dashboard pubblicata con questi stessi dati: funziona dentro il tipo Dashboard di claude.ai, non come pagina autonoma.

## Con 1 e 10 client

Profilo full, 2 ripetizioni da 1 secondo per scenario, prima una revisione e poi l'altra. La media geometrica del rapporto p95 dopo/prima è **0,64 con 1 client** (71 scenari) e **0,51 con 10 client** (15 scenari).

I guadagni maggiori sono sui percorsi che prima passavano dal processo figlio:

| Scenario | Client | p95 prima (ms) | p95 dopo (ms) |
| --- | ---: | ---: | ---: |
| member.security | 1 | 59.3 | 6.7 |
| admin.user_roles | 1 | 115.3 | 13.2 |
| guest.signature | 1 | 80.0 | 12.6 |
| journey.forum_configuration | 1 | 77.4 | 19.4 |
| journey.messages | 10 | 387.0 | 62.6 |
| journey.settings_notifications | 10 | 315.4 | 57.7 |
| journey.drafts_preview | 10 | 246.8 | 55.3 |
| journey.polls | 10 | 555.6 | 166.8 |

Due scenari risultavano peggiorati: `moderator.reports` con 1 client (21,9 → 56,3 ms) e `mixed` con 10 client (111,7 → 164,7 ms). Ripetuti da soli e in ordine alternato non lo sono: `moderator.reports` misura circa 14 ms in entrambe le revisioni, e `mixed` passa da 520 a 595 richieste medie in 3 secondi, con p95 da 124 a 103 ms.

## Con 50 e 100 client

A queste concorrenze il benchmark prova solo quattro pagine in lettura. Otto giri da 3 secondi in ordine prima, dopo, dopo, prima, dopo, prima, dopo, prima. Richieste completate in 3 secondi, media dei quattro giri con l'intervallo osservato:

| Pagina | Client | Prima | Dopo |
| --- | ---: | ---: | ---: |
| Home | 50 | 815 (763–871) | 761 (584–938) |
| Home | 100 | 845 (753–909) | 806 (707–964) |
| Discussione | 50 | 506 (428–544) | 490 (429–586) |
| Discussione | 100 | 580 (511–626) | 524 (442–636) |
| Ricerca | 50 | 756 (661–803) | 691 (577–861) |
| Ricerca | 100 | 775 (670–823) | 716 (650–885) |
| Notifiche | 50 | 962 (799–1037) | 879 (734–1005) |
| Notifiche | 100 | 1010 (889–1091) | 923 (822–1100) |

La media della revisione nuova è più bassa di circa il 7%, ma ogni intervallo si sovrappone e la differenza segue l'ordine dei giri: a coppie, la revisione precedente prevale in due casi, la nuova in uno, e uno è pari. Su queste quattro pagine il codice cambia solo per il rendering dei corpi, che usa `cpu_p` invece di `run_p` sullo stesso processo figlio.

## Costo CPU per richiesta

Per separare il codice dal rumore della macchina, l'applicazione è caricata in processo con Test::Mojo, con un utente autenticato. Tempo utente più sistema del processo e dei figli, diviso per 200 richieste; due passaggi per revisione in ordine alternato.

| Pagina | Prima (ms) | Dopo (ms) |
| --- | ---: | ---: |
| Home | 11.33 | 11.23 |
| Discussione | 18.13 | 17.80 |
| Ricerca | 11.98 | 10.83 |
| Notifiche | 9.18 | 9.23 |

Il costo è uguale o minore: il calo di throughput a 50 e 100 client non viene dal codice.

## Sessioni PostgreSQL

Contatore `sessions` di `pg_stat_database`, azzerato prima di ogni pagina; login, 3 richieste di riscaldamento e 30 misurate. Le pagine notifiche, riepilogo notifiche, messaggi, bozze, impostazioni e segnalibri passano da 6 a 4 sessioni, la home da 7 a 5. Il numero non cresce con le richieste in nessuna delle due revisioni; la sessione in meno è quella dell'esecutore isolato, e il budget per worker scende da quattro a tre connessioni.

## Limiti

- Le scritture non sono misurate a 50 e 100 client: il benchmark non le prevede.
- Una sola macchina, condivisa: a 50 e 100 client la variazione fra giri supera la differenza fra le revisioni.
- Gli output grezzi `http-complete.json` non sono conservati; le righe di [summary.json](summary.json) sono lette dalle righe di riepilogo del benchmark.
- Il tracciatore dei fork non è riuscito a osservare i worker Hypnotoad del benchmark. L'assenza di fork verso PostgreSQL è verificata dalla suite di integrazione e da `t/885-no-database-in-children.t`, non da queste misure.
