# GPForum, NodeBB e Discourse · 8 novembre 2026

Confronto fra GPForum (main a `cddae6e`), NodeBB v4.16.7 e Discourse v2026.11.0-latest sulle stesse quattro pagine, con lo stesso dataset, lo stesso PostgreSQL e lo stesso generatore. I dati completi, giro per giro, sono in [summary.json](summary.json).

## Condizioni

- **Macchina**: Apple M4 (10 core, 16 GiB), in modalità Risparmio energetico e condivisa con altre sessioni (carico a 1 minuto fra 3 e 6). I valori assoluti sono più bassi che su una macchina libera; il confronto vale all'interno di questa misura.
- **Database**: un solo cluster PostgreSQL 18.6 per tutti (shared_buffers 512MB, il resto predefinito), un database per forum.
- **Un processo applicativo per forum**:
  - GPForum: 1 worker Hypnotoad, con l'entrypoint `benchmarks/hypnotoad-app.pl` e le cache locali di `benchmark-http-complete`;
  - NodeBB: `node app.js` in produzione, su PostgreSQL senza Redis (Node 26.13);
  - Discourse: 1 worker Pitchfork in produzione, Ruby 4.0.9 con YJIT acceso e le impostazioni del garbage collector dell'immagine Docker ufficiale, Valkey 9.1.3, senza Sidekiq.
- **Dataset**: 103 utenti, 8 categorie, 240 discussioni da 20 post e 3 notifiche per utente, con gli stessi titoli e testi di `PerformanceSeed`. Le differenze inevitabili:
  - NodeBB e Discourse aggiungono 4 categorie predefinite, e Discourse 14 discussioni di sistema;
  - NodeBB mostra 6 notifiche invece di 3;
  - la ricerca mostra 20 risultati in GPForum, 10 in NodeBB e 50 in Discourse.
- **Generatore**: `wrk` con `benchmarks/wrk-metrics.lua`, connessioni keep-alive e un utente autenticato. User-Agent di Chrome e `Accept: text/html`. Ogni cella ha 2 secondi di riscaldamento e 6 di misura, per 2 giri con l'ordine dei forum ruotato.
- **CPU per richiesta**: tempo CPU dei processi del forum (per Discourse anche Valkey) e di tutti i processi PostgreSQL, prima e dopo ogni cella, diviso per le richieste completate.

Ogni pagina è il primo documento HTML completo che riceve un browser. Discourse risponde con la sua applicazione JavaScript e i dati precaricati, e carica la lista delle notifiche con una richiesta successiva, misurata a parte come `notifications.json`.

## Con 1 client

È il costo di una singola pagina, senza code. Valori medi dei due giri; per la CPU, applicazione + PostgreSQL in millisecondi.

| Pagina | Forum | Richieste/s | p95 (ms) | CPU per richiesta (ms) |
| --- | --- | ---: | ---: | ---: |
| Home | GPForum | 141.8 | 7.7 | 6.5 + 0.7 |
| Home | NodeBB | 29.7 | 34.7 | 10.8 + 30.6 |
| Home | Discourse | 8.6 | 123.0 | 93.0 + 23.0 |
| Discussione | GPForum | 96.8 | 11.5 | 9.5 + 1.1 |
| Discussione | NodeBB | 45.6 | 23.1 | 9.0 + 17.3 |
| Discussione | Discourse | 6.6 | 159.0 | 117.2 + 30.7 |
| Ricerca | GPForum | 148.4 | 8.2 | 6.6 + 0.3 |
| Ricerca | NodeBB | 10.8 | 99.3 | 9.8 + 90.2 |
| Ricerca | Discourse | 7.9 | 133.7 | 91.0 + 35.6 |
| Notifiche | GPForum | 192.9 | 5.7 | 4.9 + 0.5 |
| Notifiche | NodeBB | 49.2 | 22.3 | 8.2 + 16.5 |
| Notifiche | Discourse | 10.2 | 100.6 | 72.4 + 21.5 |

Rispetto a NodeBB, GPForum è circa 2 volte più rapido sulla discussione, 4–5 sulla home e sulle notifiche, 14 sulla ricerca. Rispetto a Discourse è circa 15–20 volte più rapido su tutte e quattro le pagine. La sola lista delle notifiche di Discourse in JSON costa 7.5 + 1.6 ms, con p95 di 10,3 ms.

## Con 10 e 50 client

| Pagina | Client | GPForum | NodeBB | Discourse |
| --- | ---: | ---: | ---: | ---: |
| Home | 10 | 163.8 req/s · p95 52 ms | 115.4 · 77 ms | 7.1 · 1551 ms |
| Home | 50 | 157.7 · 307 ms | 109.1 · 506 ms | saturo |
| Discussione | 10 | 106.1 · 90 ms | 135.6 · 69 ms | 5.7 · 1794 ms |
| Discussione | 50 | 108.7 · 481 ms | 134.8 · 377 ms | saturo |
| Ricerca | 10 | 149.9 · 58 ms | 66.8 · 130 ms | 6.6 · 1662 ms |
| Ricerca | 50 | 149.3 · 347 ms | 73.1 · 806 ms | saturo |
| Notifiche | 10 | 219.4 · 38 ms | 158.8 · 56 ms | 9.2 · 1182 ms |
| Notifiche | 50 | 203.3 · 260 ms | 152.4 · 333 ms | saturo |

Con un solo processo, GPForum regge più richieste di NodeBB su home, ricerca e notifiche, ma non sulla discussione. Lì il worker Perl si satura: spende circa 9,4 ms di CPU propria per pagina, cioè poco più di 100 pagine al secondo. NodeBB ne spende 8 nel processo Node e sposta circa 18 ms su PostgreSQL, che gira su altri core. In CPU totale la discussione costa 10,6 ms in GPForum, 26,3 in NodeBB e 148 in Discourse.

Discourse serve una richiesta alla volta per worker: con 10 client la coda supera il secondo, e con 50 le richieste scadono (timeout di 2 secondi di `wrk`). La sua configurazione predefinita prevede 3 worker. Più worker moltiplicano le richieste al secondo, non abbassano il costo per pagina.

## Osservazioni su GPForum

- Con `Accept: text/html,application/json`, GPForum risponde in JSON anche se HTML è elencato per primo. Una prima misura con quell'intestazione è stata scartata.
- La home in JSON costa circa 47 ms per richiesta, contro i circa 10 della pagina HTML, e con 10 client non supera le 37 richieste al secondo.

## Limiti

- Un solo processo applicativo per forum: è un confronto di costo per richiesta, non di capacità massima di ciascun prodotto.
- Solo letture: niente scritture, caricamenti, tempo reale o lavori in background.
- Il campionamento CPU non conta i processi figli di breve durata.
- Il server GPForum è partito alle 20:37 dal main di allora (`cddae6e`). Il commit `0c4f484`, arrivato alle 20:44, non è incluso.
- Gli output grezzi di `wrk` non sono conservati: i valori di ogni giro sono in [summary.json](summary.json). Le installazioni di NodeBB e Discourse sono state rimosse dopo la misura.
