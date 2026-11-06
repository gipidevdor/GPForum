# Revisione del nucleo Perl · 6 novembre 2026

La revisione interviene su correttezza dei contratti, limiti delle cache e lavoro
ripetuto nel livello SQL. La base è `7ccd164dabea8686824022d0928936d7b74ff1bf`; passkey e Web Push in
lavorazione nel checkout condiviso sono esclusi. Non è una certificazione di
perfezione dell'intera applicazione.

## Correzioni

- **PreparedQuery:** un IN più lungo perdeva elementi, una condizione NULL poteva
  riusare `= NULL` e un limite mancante poteva rendere illimitata una lettura.
  Ora le forme incompatibili eseguono il resultset corrente. Il test su PostgreSQL
  [fallisce in quattro casi sul codice precedente](runs/baseline-prepared-red-final/run.log)
  e [passa sul candidato](runs/candidate-prepared-final/run.log).
- **SqlFunction:** chiavi senza collisioni per confini dei parametri, array vuoti,
  elementi vuoti e NULL, inclusi array annidati. Il binding legge i parametri
  senza copiare e svuotare l'hash del chiamante; classificazione UUID/bytea
  precalcolata nel catalogo e nomi delle colonne JSON raccolti una volta per chiamata.
- **LocalCache/TieredCache:** lookup conta e aggiorna la recenza, espone la
  scadenza originale e impedisce a un riempimento L1 di allungare la vita L2.
  I tag sono copiati e normalizzati: modificarli fuori dalla cache non lascia
  riferimenti orfani nell'indice. Un solo campionamento dell'orologio per hit
  e per una passata di pulizia.
- **Osservazione SQL:** CountedQuery e PreparedQuery chiudono l'intervallo anche
  quando DBI fallisce, conservando l'eccezione originale. Le durate delle richieste
  usano un orologio monotono; limiti di cronologia invalidi sono rifiutati prima
  che possano bloccare il ciclo di rimozione.
- **Rendering:** un risultato troppo grande per la memo viene restituito senza
  espellere i corpi già caldi.

## Verifiche

La [suite generale](runs/unit-final/run.log) passa **686 file / 20.655 controlli**.
Le integrazioni coprono **161 file**, con **14.393 controlli finali**: il primo
[run](runs/integration/run.log) ha superato 160 file e rilevato un nome di colonna
errato nella nuova fixture; corretto il test, [il file interessato passa 40 controlli](runs/candidate-prepared-final/run.log).
Non abbiamo ripetuto i 160 file già passati. La fixture iniziale è conservata.

[Perl::Critic sull'intero albero](runs/critic/run.log) segnala zero violazioni;
[sintassi, perltidy e architettura](runs/static/run.log) passano. Le successive
rifiniture delle chiavi e dell'avvio hanno superato
[1.960 controlli mirati](runs/refinement-unit/run.log),
[404 controlli PostgreSQL/HTTP](runs/refinement-integration/run.log),
[il controllo finale del protocollo](protocol-final.log) e
[Perl::Critic sui file modificati](runs/focused-critic-pass-2/run.log).
I test aggiunti vengono eseguiti anche sul codice precedente, dove
[espongono i difetti](runs/baseline-core-red/run.log).

Il primo run generale ha incontrato un problema indipendente del verificatore
dei link: controllava una copia parziale `source-untracked` come documentazione
corrente. Lo snapshot di verifica include la correzione di una riga già presente
nel checkout condiviso, coerente con le altre esclusioni degli archivi; i documenti
correnti restano verificati. È supporto di test, escluso dal codice misurato.

## Misure finali, eseguite dopo la revisione

Ordine **prima/dopo/dopo/prima**. Tre batch per caso in ogni avvio, quindi mediana
di sei batch per lato. Intervalli min–max osservati, non intervalli di confidenza.
Il caso con DB simulato misura il livello Perl e non esegue PostgreSQL: questi
valori non sono richieste HTTP al secondo.

| Caso Perl | Prima op/s | Dopo op/s | Variazione | Intervalli sovrapposti |
| --- | ---: | ---: | ---: | --- |
| Lettura cache locale | 345346 | 407252 | +17.9% | no |
| Sostituzione cache locale | 101240 | 99244 | -2.0% | sì |
| Chiave per 25 post | 187806 | 106513 | -43.3% | no |
| Binding SQL, 6 parametri | 217599 | 247458 | +13.7% | no |
| Call layer, DB simulato | 84737 | 95230 | +12.4% | no |

La chiave sicura costa più del precedente join ambiguo. La prima implementazione
sicura è stata alleggerita evitando una chiamata Perl per ogni elemento piatto;
una variante JSON è stata [misurata e scartata](key-options.log) perché più lenta.
Il costo finale resta esposto nella tabella. La variazione delle scritture di
cache ha intervalli sovrapposti e non viene classificata come regressione confermata.

### HTTP reale, quattro worker

**24 celle / 17.371 richieste / zero errori inattesi**.
Ogni punto è la mediana di quattro celle; p95 e p99 sono mediane dei percentili
delle celle, non percentili uniti. Thread autenticato, 240 thread / 4.800 post,
concorrenza 1/32/100, due ripetizioni, 40 letture seriali, cinque warmup e celle
concorrenti di tre secondi. Stesso hardware e generatore locale del confronto
precedente, PostgreSQL e applicazione sulla stessa macchina, senza proxy/TLS.

| Client | Prima req/s | Dopo req/s | Variazione | Prima p95 ms | Dopo p95 ms | Prima p99 ms | Dopo p99 ms |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 82.0 | 81.7 | -0.4% | 12.5 | 13.0 | 13.2 | 13.4 |
| 32 | 343.8 | 341.9 | -0.5% | 104.5 | 108.3 | 140.6 | 143.1 |
| 100 | 346.7 | 344.4 | -0.7% | 371.1 | 384.4 | 1259.6 | 1312.5 |

Gli intervalli di throughput HTTP si sovrappongono a ogni concorrenza. Queste
prove **non dimostrano un aumento del throughput dell'intera applicazione**;
le differenze sono piccole rispetto alla variabilità osservata. Il p99 sotto
forte carico resta un limite aperto. Il guadagno misurato nel Perl non va
trasformato in una percentuale promessa al sito. Le prove sono brevi e su una
workstation; il monitor non ha rilevato carichi concorrenti noti nei run finali.

### Avvio del generatore

Un tentativo intermedio è [fallito prima di raccogliere celle](runs/after-b-http/http/http-complete.json):
era disponibile la telemetria di tre worker su quattro. Le sonde seriali possono
continuare a raggiungere un sottoinsieme dei worker. L'avvio ora usa una piccola
serie di sonde concorrenti e continua a richiedere la telemetria di ogni PID,
EV nativo e template ereditati compilati entro il limite esistente. I test
verificano che tutte le richieste inizino prima della prima risposta e che il
limite di avvio resti vincolante. Il profilo HTTP non cambia.

Questa correzione è applicata **a entrambi i lati** del confronto finale,
interamente prima della misura. I tentativi iniziali con la prima versione delle
chiavi e le sonde seriali restano nell'inventario; non alimentano le tabelle finali.
Le impronte dei sorgenti sono rilevate prima e dopo ogni run finale e devono
coincidere. Nessun retry delle richieste misurate e nessun cambiamento a worker,
quote, cache di pagina o impostazioni PostgreSQL fra i due lati.

## Dati e riproduzione

- [Risultati e configurazione JSON](summary.json), [CSV dei casi Perl](comparison.csv)
- [Inventario di tutti i tentativi](run-inventory.json)
- [Sorgenti e impronte](source-manifest.json)
- [Patch applicativa](application.patch), [harness comune](harness.patch), [test](verification.patch)
- [Driver Perl dei microbenchmark](benchmark.pl), [checksum](SHA256SUMS)

Ricostruire due checkout del commit indicato con le dipendenze bloccate; applicare
harness.patch a entrambi e application.patch al candidato. verification.patch
aggiunge i test al candidato. Il driver Perl parte dalla directory dello snapshot:

```sh
script/gpforum-carton exec perl /percorso/benchmark.pl
```

Per HTTP, usare directory di output nuove e alternare i due snapshot nello stesso
ordine delle tabelle. Il generatore crea e distrugge il proprio PostgreSQL:

```sh
script/gpforum-carton exec script/benchmark-http-complete --output artifacts/perl-repro-001 --workers 4 --iterations 40 --warmup 5 --duration 3 --repetitions 2 --concurrency 1,32,100 --deadline 300 --scenario member.thread
```

I JSON conservano comandi e configurazioni esatti. Le variabili GPFORUM_/PG e le
forzature MOJO_REACTOR/LIBEV_FLAGS ereditate vanno rimosse dalla shell di prova.
Non è stato modificato alcun database del servizio.
