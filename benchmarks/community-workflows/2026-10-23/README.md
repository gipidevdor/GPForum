# Community workflow validation — Apple M4

100 letture seriali a cache calda di un sondaggio con 1.000 votanti sintetici
e tre opzioni, PostgreSQL 18.6 (Homebrew), Apple M4 / 16 GiB. Il tempo
client comprende il call layer Perl e la funzione PostgreSQL sul socket Unix.

| p50 | p95 | p99 |
| ---: | ---: | ---: |
| 0.180 ms | 0.232 ms | 0.288 ms |

È una verifica diagnostica singola, non una misura di capacità HTTP o una prova
A/B. Non dimostra miglioramenti rispetto alla baseline M4 precedente. Il cluster
temporaneo usa le impostazioni effettive registrate in metadata.json.

- `poll-read.json`: tutti i campioni e i piani ANALYZE/BUFFERS delle letture interne
  di opzioni e voto personale. La seconda usa un lookup indicizzato; i totali
  provengono dalle opzioni, senza scansione dei votanti.
- `validation.tap`: inviti, approvazione in entrambi gli ordini rispetto alla
  verifica email, concorrenza, contatori, privacy, trasferimenti/ripristino e
  moduli web con CSRF valido e non valido. Otto subtest principali.
- `metadata.json`: hardware, PostgreSQL, impostazioni e impronte dei sorgenti.

Riproduzione su un server di test con CREATEDB, mai su un database di produzione:

```sh
GPFORUM_TEST_DSN='dbi:Pg:dbname=postgres;host=SOCKET;port=PORT' \
GPFORUM_DATABASE_USER=ROLE \
GPFORUM_COMMUNITY_EVIDENCE=/tmp/poll-read.json \
script/gpforum-carton exec prove -lv -It/lib t/integration/postgres-community-completion.t
```

Il test crea, migra e cancella un proprio database. Non richiede modifiche
globali al server o al runner. `metadata.json` identifica la base pubblicata e
le versioni dei file misurati nel working tree.

## Verifica dell’attivazione locale

`activation.json` registra separatamente l’attivazione sul database di sviluppo,
gli esiti CI del fix `7fd2c40` e una lettura di `pg_settings` con unità, origine e
`pending_restart`. Non aggiunge campioni al benchmark dei sondaggi.

La suite Debian passa 603 file e 29.647 test; CI e Perl::Critic sono verdi.
Sul cluster locale il profilo condiviso dichiarato per 16 GiB, con 8 GiB di
riserva, segnala otto differenze: `verify --strict` restituisce correttamente 1.
Non è stato applicato tuning al cluster condiviso. Durabilità e autovacuum sono
attivi. La readiness resta `degraded` per il profilo non dichiarato nell’ambiente
del server e 75 notifiche sintetiche storiche in `DEFAULT`; i dati sono preservati.
Il gate CI separato da 5.000 connessioni resta fallito ed è registrato come limite.
