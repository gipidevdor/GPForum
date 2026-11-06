# Benchmark GPForum su Apple M4

Eseguito il 23 ottobre 2026 (Europe/Rome); percorso e timestamp dei dati in UTC.

Codice misurato: `b5cc464db7bdcf1a61002d59875c72ce8c8edd2c`. Esportazione esatta del commit pubblicato; le modifiche UI non committate delle altre sessioni sono escluse.

Apple M4, 4 core performance e 6 efficiency, 16 GiB RAM, macOS 27.0.1; alimentazione di rete, filesystem APFS. PostgreSQL 18.6, Perl 5.44.0, Mojolicious 9.49, EV 4.37 con kqueue e wrk 4.2.0. Applicazione, generatore e database condividono il portatile.

## Esito e protocollo

96 campioni HTTP e 63 finestre su socket. Errori HTTP/trasporto: 0/0; stati inattesi sulle pagine/form: 0. Tre ripetizioni per ogni scenario, controllate nei dati grezzi.

Le tabelle riportano la mediana delle tre ripetizioni, anche per i percentili. Il CSV riporta inoltre minimo, massimo e deviazione assoluta mediana del throughput; non si aggregano generatori o dataset diversi. Le connessioni configurate non equivalgono a utenti attivi.

## Configurazione PostgreSQL

| Parametro | Valore |
| --- | --- |
| effective_cache_size | 6144MB |
| effective_io_concurrency | 100 |
| jit | off |
| maintenance_work_mem | 128MB |
| max_connections | 100 |
| random_page_cost | 1.1 |
| shared_buffers | 2048MB |
| track_io_timing | on |
| work_mem | 4MB |

Profilo `shared`, 8 GiB riservati a sistema, applicazione e altri processi. `fsync`, `full_page_writes`, `synchronous_commit` e `autovacuum` rimangono attivi. [Verifica strict](postgres-verify.json), [piano](postgres-plan.json), [journal applicazione](postgres-apply.jsonl). Il profilo è stato applicato solo al cluster temporaneo del benchmark.

## Uso del forum: quattro worker, socket Unix

Servizio in modalità production, EV/kqueue, connessioni keep-alive dirette al socket con gli header del proxy. Dataset medium: 25 utenti iniziali, 8 categorie, 120 thread e 1.800 post; altri 400 account sono registrati e autenticati attraverso le pagine. Le letture autenticate usano otto identità; le scritture ruotano su 400 account. Sono testati c=1/8/32. Letture: 6 s dopo 2 s di warmup; scritture: 3 s dopo 0,5 s. Le seguenti righe sono a c=32.

| Percorso | req/s | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Thread autenticato | 424,5 | 73,51 | 85,42 | 91,32 |
| Thread anonimo, cache calda | 5.325,3 | 5,96 | 8,86 | 9,89 |
| Homepage autenticata | 646,0 | 47,25 | 56,07 | 58,91 |
| Categoria autenticata | 799,0 | 39,33 | 49,01 | 57,21 |
| Ricerca autenticata | 488,0 | 66,34 | 76,52 | 80,44 |
| Risposta tradizionale (302) | 732,0 | 41,74 | 54,61 | 63,97 |
| Risposta HTMX con frammento HTML | 368,7 | 87,22 | 114,57 | 122,33 |

I limiti di lettura sono elevati per consentire il carico. Il limite di scrittura resta quello del prodotto, ma il benchmark azzera i contatori fra le finestre: questi valori descrivono brevi finestre e non un ritmo sostenibile per account. Il POST tradizionale termina al redirect: non comprende il caricamento successivo del thread. HTMX comprende il frammento di risposta e il nuovo composer. Il controllo intermedio sul database ha verificato post e relativi corpi effettivamente salvati: [verifica scritture](socket-write-correctness.json), che comprende warmup e una parte della corsa, non un totale finale. Il censimento delle connessioni è diagnostico: a basso carico alcuni conteggi per worker possono risultare negativi e non vengono usati per ricavare capacità.

[Tutte le finestre su socket](socket-samples.jsonl) · [Resoconto originale](socket-report.txt)

## Letture anonime su 72.000 post

600 thread da 120 post, 40 utenti e 4 categorie. Generatore indipendente wrk; TCP loopback, senza TLS né reverse proxy. Tre campioni da 3 s per scenario; c=1/10/50. Due worker per la matrice principale e confronti mirati con 4/8 worker su thread, ricerca e cache. Le righe sottostanti distinguono numero di worker e concorrenza.

| Percorso | Worker | c | req/s | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| cache_hit | 2 | 10 | 2.741,9 | 3,97 | 4,40 |
| cache_hit | 4 | 50 | 4.996,9 | 16,71 | 18,33 |
| cache_hit | 8 | 50 | 7.562,8 | 14,50 | 17,43 |
| cache_miss | 2 | 10 | 1.132,7 | 10,45 | 15,05 |
| categories | 2 | 10 | 2.732,7 | 4,46 | 4,72 |
| category | 2 | 10 | 2.676,3 | 4,67 | 5,26 |
| health_live | 2 | 10 | 3.279,3 | 3,31 | 3,73 |
| home | 2 | 10 | 480,8 | 26,64 | 29,23 |
| search | 2 | 10 | 213,1 | 58,46 | 61,85 |
| search | 4 | 50 | 387,9 | 198,40 | 247,90 |
| search | 8 | 50 | 643,1 | 139,53 | 176,51 |
| thread | 2 | 10 | 2.617,9 | 4,65 | 5,78 |
| thread | 4 | 50 | 4.607,3 | 14,80 | 20,66 |
| thread | 8 | 50 | 6.976,6 | 12,96 | 16,32 |

La prova `cache_miss` invalida la cache SSR mantenendo caldo il modello categoria: non è una prova con cache disco o PostgreSQL fredda. Le sei misure del generatore Mojo sono controlli aggiuntivi e restano distinte dalle 90 misure wrk. [HTTP grezzo](http.json) · [Dataset/configurazione](http-environment.json)

## Ricerca: 100.000 e 1.000.000 documenti

Benchmark di servizio seriale già presente nel repository, con SQL-function API reale. Tre corse per scala; 50 campioni di lettura a 100k, 20 a 1m, 30 campioni di scrittura e 5 warmup per operazione. Il corpus sintetico include ricerche comuni (`the`), rare (`zymurgy`), trigram (`perf thrd`) e autocomplete. L’autocomplete temporizzato usa il prefisso `Dep` del fixture; il piano aggiuntivo usa il prefisso più ampio `Per`. Il trigram usa un caso ampio con molti titoli simili. Non equivale a un forum completo con un milione di post e corpi. I percentili su 20/50 campioni sono indicativi; il throughput è seriale, non capacità HTTP concorrente.

| Documenti | Operazione | op/s seriali | p50 ms | p95 ms | p99 ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 100k | search_full_text_common | 3,53 | 280,83 | 295,92 | 299,53 |
| 100k | search_full_text_rare | 657,31 | 1,49 | 1,77 | 1,92 |
| 100k | search_trigram | 3,22 | 309,92 | 322,35 | 337,00 |
| 100k | search_autocomplete | 178,98 | 5,57 | 5,81 | 6,46 |
| 100k | thread_page_member | 2.283,11 | 0,42 | 0,48 | 0,71 |
| 100k | home_page_member | 758,04 | 1,29 | 1,46 | 1,70 |
| 100k | category_index_member | 2.018,16 | 0,48 | 0,58 | 1,00 |
| 100k | new_thread | 700,95 | 1,37 | 1,83 | 2,53 |
| 100k | reply | 780,34 | 1,20 | 1,63 | 1,90 |
| 1m | search_full_text_common | 87,57 | 11,20 | 12,63 | 13,90 |
| 1m | search_full_text_rare | 346,93 | 2,74 | 3,14 | 3,69 |
| 1m | search_trigram | 0,32 | 3.148,30 | 3.193,54 | 3.194,55 |
| 1m | search_autocomplete | 179,48 | 5,52 | 5,82 | 6,22 |
| 1m | thread_page_member | 2.138,10 | 0,43 | 0,54 | 0,84 |
| 1m | home_page_member | 719,66 | 1,35 | 1,53 | 1,69 |
| 1m | category_index_member | 1.868,29 | 0,50 | 0,67 | 0,83 |
| 1m | new_thread | 647,91 | 1,51 | 2,03 | 2,22 |
| 1m | reply | 746,90 | 1,27 | 1,65 | 2,36 |

**Il trigram a 1m supera il normale budget web di 2 s.** Questo harness usa una sessione da 15 s: misura il costo SQL ma non dimostra che tale ricerca completi entro il limite del sito.

I sei file `service-100k-r*.json` e `service-1m-r*.json` conservano campioni, conteggi e digest del corpus, CPU client/backend, RSS, contatori buffer/I/O/WAL, indici, statistiche e piani auto_explain ANALYZE/BUFFERS/WAL delle query interne. Le scritture del servizio fanno crescere la fixture fra le corse; conteggi e digest sono riportati in `local-summary.json`. Il planner può scegliere piani diversi alle due scale: a 100k la ricerca comune usa GIN/trigram e molti lookup di visibilità; a 1m usa l’indice temporale. Il tempo minore su quel singolo caso a 1m non misura un miglioramento generale. `search-plan-overview.json` distingue i piani normali da quelli con indici forzati, che sono solo diagnostici.

## Outbox PostgreSQL

3.000 messaggi, batch di 100, tre ripetizioni per numero di worker. Dispatcher reale, connessioni PostgreSQL indipendenti e trasporto no-op. I percentili sono di batch, non tempi di consegna individuali né costo di email reali.

| Worker | messaggi/s | batch p50 ms | batch p95 ms | batch p99 ms | Persi | Duplicati |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 2.109,3 | 45,95 | 49,26 | 53,02 | 0 | 0 |
| 2 | 3.565,5 | 53,49 | 59,57 | 60,09 | 0 | 0 |

Il primo raccoglitore ha troncato a 200.000 byte il JSON PostgreSQL 18, rendendolo illeggibile. Il workload è stato ripetuto con stdout completo e stderr separato; il risultato valido è stato importato dal punto di estensione esistente di Hotpaths, con gli stessi parametri e la stessa conversione delle metriche. La prima anomalia resta registrata. Nessun risultato misurato è stato ricostruito o stimato.

[Output outbox completo](outbox-full.json) · [Traccia recupero](outbox-capture-recovery.json)

## Risorse e limiti

CPU/RSS HTTP sono conservate per finestra. Le risorse di sistema sono campionate ogni 2 s nel blocco principale; la ripetizione outbox conserva i propri campioni di worker e backend. I contatori PostgreSQL sono fotografati fra le fasi. La CPU di servizio copre i campioni temporizzati; buffer/I/O/WAL includono anche warmup e attività di checkpoint/autovacuum. Su macOS la percentuale CPU di ps è una media dalla nascita del processo, non un costo per richiesta. La RSS include pagine condivise: sommare i backend PostgreSQL sovrastima la memoria privata. I block read PostgreSQL possono essere serviti dalla cache del sistema operativo.

| Scala servizio | CPU client s, mediana per corsa | CPU backend s, mediana per corsa | WAL MiB, mediana per corsa | Buffer hit %, mediana |
| --- | ---: | ---: | ---: | ---: |
| 100k | 0,40 | 30,58 | 1,18 | 100,00 |
| 1m | 0,19 | 63,47 | 1,14 | 100,00 |

Sono rimaste attive le applicazioni desktop, gli altri cluster e i servizi di sistema. Il carico di background è riportato in `host-resources.jsonl`; i core performance ed efficiency non sono intercambiabili. Il test non isola affinità o throttling termico. Campioni brevi e dataset sintetici descrivono queste condizioni del portatile, non una capacità garantita di produzione. Il login del fixture amministra il solo cluster temporaneo; il test non verifica l’isolamento del ruolo runtime di produzione.

Non c’è un confronto A/B con una revisione precedente o un diverso tuning. Le misure non giustificano dichiarazioni di miglioramento rispetto ai run storici o ai runner Linux.


### Memoria e CPU dell’applicazione HTTP

RSS alla fine delle finestre, somma manager e worker: include pagine condivise e non è memoria privata né un picco. CPU da ps, indicativa. Valori mediani su tre prove.

| Percorso | Worker | c | RSS MiB | CPU % ps |
| --- | ---: | ---: | ---: | ---: |
| cache_hit | 4 | 50 | 347.8 | 386.3 |
| search | 4 | 50 | 356.6 | 202.7 |
| thread | 4 | 50 | 396.1 | 388.6 |

Nel blocco HTTP il carico di background mediano osservato da ps è 196.8% (100% corrisponde a un core logico). [Aggregati risorse host](host-resource-summary.json).

## File e riproduzione

- `local-summary.json`: aggregati e controlli di completezza; `latency-throughput.csv`: tutte le combinazioni aggregate.
- `metadata.json`, `hardware.json`, `host-storage-power.json`: provenienza e macchina.
- `commands.json`: argomenti eseguiti, dimensioni e timeout; i percorsi temporanei richiedono un nuovo cluster isolato per riprodurre la prova.
- `report.md` e `summary.json`: report e schema della raccolta continua; `database.json`: piani e query budgets.
- `postgres-before.json`, `postgres-after-http.json`, `postgres-after-socket.json`, `postgres-after-all.json`: contatori PostgreSQL per fase.
- `source-manifest.json` e `SHA256SUMS`: impronte di sorgenti e risultati.

Usare i medesimi script sulla revisione indicata, un cluster temporaneo con il profilo shared riportato e le dimensioni dei comandi. Preparazione, migrazioni e autenticazione iniziale non rientrano nei campioni temporizzati. Non vengono inviati messaggi o richieste a servizi esterni.
