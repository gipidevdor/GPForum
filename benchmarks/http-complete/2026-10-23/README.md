# Benchmark HTTP completo — 23 ottobre 2026

Evidenza locale su Apple M4 / 16 GiB: Hypnotoad reale su TCP loopback,
PostgreSQL 18.6, Perl 5.44.0, Mojolicious 9.51, EV/kqueue. Database temporaneo
con `fsync`, `full_page_writes` e `synchronous_commit` attivi.

Il run completo con due worker passa **38.011 richieste in 264 celle**;
67 scenari di lettura, sette flussi di scrittura, carico misto e login/logout.
Tre ripetizioni; letture concorrenti a 1/10/50/100 sessioni, scritture a 10 client.
Nessun errore HTTP o di dominio. Copertura osservata: **105/191 rotte**;
le altre 86 sono elencate nel JSON e nel report. Non equivale a copertura totale.

- [Diagnosi e confronto leggibile](http-complete-full-20261023/diagnosis.html)
- [Dati grezzi del run completo](http-complete-full-20261023/http-complete.json)
- [Tutte le operazioni e celle](http-complete-full-20261023/report.html)
- [Confronto strutturato](http-complete-full-20261023/comparison.json)
- [Confronto mirato con quattro worker](http-complete-workers4-retry-20261023/http-complete.json)
- [Tentativo a quattro worker escluso](http-complete-workers4-20261023/http-complete.json)

## Risultati a 100 sessioni

Mediane delle tre ripetizioni per ogni configurazione; celle di tre secondi.

| Scenario | req/s, 2 worker | req/s, 4 worker | p95 ms, 2 worker | p95 ms, 4 worker |
| --- | ---: | ---: | ---: | ---: |
| Thread autenticato | 170,01 | 290,38 | 1.149,71 | 645,44 |
| Ricerca autenticata | 212,98 | 368,70 | 917,71 | 699,27 |

Il tempo applicativo mediano del thread resta circa 10 ms, il DB circa 1 ms;
per la ricerca, circa 8 ms e 3–4 ms. La crescita del throughput con più worker
e del tempo fuori app sotto carico indica saturazione della capacità dei
worker in questa prova. Il tempo fuori app comprende anche client e trasporto:
non è una misura esclusiva della coda. A quattro worker il p95 dei thread a
100 client varia fra 569 e 955 ms: le code hanno variabilità significativa.

L'export mbox di categoria richiede circa 287 ms anche a un client, di cui
37 ms nel DB. I soli 12 campioni non permettono di caratterizzare il p99.
POST login, a dieci client, ha p95 460 ms, mediana applicativa 73 ms e DB 1,7 ms.

Verifica finale delle scritture: **190 thread e 407 risposte** con ID unici;
delta persistiti: 190 thread e 597 post, compresi i post iniziali e il setup
fuori misura. Il confronto mirato con quattro worker passa 18.411 richieste
in 24 celle, sugli stessi seed di thread e ricerca prima delle scritture.

Il primo tentativo a quattro worker fallisce durante l'avvio perché non ottiene
telemetria da tutti i worker entro il timeout; contiene zero celle misurate.
Resta archiviato come fallito, senza contributo al confronto prestazionale.

## Provenienza e limiti

Il codice applicativo parte da `6132905077e16de37f997175eb8a257bae303893`.
I run misurano il working tree con il nuovo harness non ancora committato:
`metadata.dirty` resta vero e il commit nei dati identifica la base, non una
revisione pulita del benchmark. `source-context.json` conserva gli hash raccolti
del harness. Prima del commit sono stati rifiniti gestione dei fallimenti,
metadati/checkpoint e presentazione; tali hash possono quindi differire dal
sorgente finale. I JSON misurati sono copie byte per byte degli artefatti.
I report HTML sono presentazioni generate dai JSON; il riepilogo qui archiviato
rimuove un riferimento a un precedente profilo non incluso in questo pacchetto.

SSR cache normale, sessioni/cookie, CSRF, autorizzazione e comandi PostgreSQL
reali. Le quote di ammissione sono alzate nel solo entrypoint benchmark;
i contatori PostgreSQL restano attivi. Consegna in background e listener realtime
disattivati. Allegati con ClamAV, SMTP/WebSub esterni, completamento token email,
MFA e connessioni realtime lunghe non sono misurati. Restano ulteriori rotte
non esercitate, elencate nei dati. Nessun TLS, proxy, WAN o rendering browser.

Generatore Mojo, applicazione e database condividono il portatile. I risultati
non sono intercambiabili con wrk, non sono un confronto alternato A/B e non
stabiliscono la capacità di produzione. Questo formato diagnostico resta
separato dagli indici e dallo schema storico `performance-http`.

## Riproduzione

```sh
script/gpforum-carton exec script/benchmark-http-complete \
  --output artifacts/http-new --profile full
script/gpforum-carton exec script/benchmark-http-complete \
  --output artifacts/http-new-4 --workers 4 \
  --scenario member.thread --scenario member.search
```

Ogni output deve essere nuovo. Il comando crea, migra e arresta il proprio
cluster PostgreSQL e Hypnotoad, ignorando il DSN ereditato. Protocollo completo
in [benchmarks/README.md](../../README.md). `SHA256SUMS` identifica tutti i file
archiviati, escluso il manifest stesso.
