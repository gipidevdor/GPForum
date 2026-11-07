# Regressioni e throughput · 6 novembre 2026

Confronto locale **prima/dopo/dopo/prima**, con quattro worker, su due snapshot
immutabili derivati da `2713b813f2553e16471dcaf93da154341e607e14`. Il confronto finale comprende
**144 celle, 162.579 richieste HTTP e 0 errori inattesi**. Tutti i
conteggi delle scritture corrispondono alle identità persistite. Le prove fallite,
intermedie e contaminate sono conservate separatamente, senza scegliere celle
favorevoli per sostituirle.

Una **cella** è una misura di uno scenario a una data concorrenza e ripetizione:
per esempio `member.thread`, 32 client, ripetizione 2. Il numero di worker vale
per l'intero run. Le 144 celle sono quattro avvii da 36 misure ciascuno; ogni
cella contiene molte richieste HTTP.

## Risultati a parità di quattro worker

Mediana di sei celle per scenario/concorrenza: due avvii indipendenti, ciascuno
con tre ripetizioni. p95 è la mediana dei p95 delle celle, non il percentile di
campioni uniti. Gli intervalli nel JSON/CSV sono min–max osservati, non intervalli
di confidenza. Intervalli disgiunti descrivono queste ripetizioni locali e non
garantiscono capacità in produzione.

| Percorso | Client | Prima req/s | Dopo req/s | Variazione | Prima p95 ms | Dopo p95 ms | Intervalli req/s sovrapposti |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Home autenticata | 100 | 599.7 | 658.0 | +9.7% | 269.9 | 163.7 | no |
| Thread autenticato | 32 | 276.6 | 335.5 | +21.3% | 334.6 | 114.1 | no |
| Thread autenticato | 100 | 293.5 | 343.0 | +16.9% | 597.8 | 331.5 | no |
| Selettore trasferimenti | 1 | 41.6 | 220.8 | +431.2% | 25.3 | 4.7 | no |
| Pubblicazione e azioni | 10 | 360.7 | 382.5 | +6.0% | 44.9 | 42.6 | sì |
| Carico misto | 10 | 322.2 | 364.8 | +13.2% | 63.0 | 53.0 | sì |

Il salto del selettore e i miglioramenti del thread sotto concorrenza si ripetono
con intervalli di throughput disgiunti. Il carico misto e la pubblicazione hanno
intervalli sovrapposti: le loro variazioni restano osservazioni, senza classificarle
come miglioramenti confermati. Tutte le altre celle, incluse quelle a basso carico,
sono in [comparison.csv](comparison.csv) e [comparison.json](comparison.json).

Il guadagno non vale per tutti i percentili. Sul thread a 32 client il p50 passa
da 37,4 a 92,8 ms mentre p95 e p99 migliorano (p99 da 449,7 a 156,9 ms).
A **100 client il p99 peggiora da 852,0 a 1.198,5 ms**,
con intervalli osservati disgiunti (prima 556,9–1.041,7; dopo 1.182,0–1.221,9).
Il dato comprende nuove connessioni all'inizio di ogni cella; non abbiamo isolato
la causa di questa coda. È un compromesso irrisolto della configurazione a quattro
worker e non viene classificato come regressione di latenza corretta. Gli altri
percentili e le distribuzioni originali restano nei JSON delle celle.

## Cause e correzioni

- **Permessi ripetuti nel selettore.** La precedente funzione risolveva utente e
  grant per ogni thread candidato. La migrazione 2041 introduce v3/v4 e calcola
  i grant una volta per la lista; la sorgente selezionata conserva il proprio
  controllo di accesso. v1/v2 restano disponibili per i vecchi worker. Test
  differenziali confrontano risposte con grant globali/categoria/spazio, revoche,
  sospensioni, antenati privati/eliminati, poll e cursori. Un contatore PostgreSQL
  verifica una sola risoluzione del viewer per una lista senza sorgente, anche
  con più candidati del limite di pagina.
- **Connessioni TCP sbilanciate.** Nella fase intermedia un worker ha servito
  240/400 richieste della pubblicazione (sei client su dieci), mentre i tempi
  applicativi e SQL restavano vicini al baseline. L'accettazione TCP ora usa
  `single_accept=1`, già usato dai listener Unix. Le scelte esplicite, incluso
  `single_accept=0`, sono rispettate. Le distribuzioni per PID restano nei JSON.
  Questa correzione riguarda TCP: il listener Unix predefinito aveva già tale
  comportamento.
- **Lavoro di presentazione.** Icone/etichette delle reazioni sono riusate nella
  stessa risposta; i post senza card non eseguono il relativo partial. CSRF,
  autorizzazioni e identità dei comandi restano freschi. Da sola, questa parte
  aveva prodotto variazioni piccole e sovrapposte: non le attribuiamo il guadagno
  del confronto finale.
- **Separazione delle celle.** Un candidato intermedio ha avuto sette chiusure
  premature nella home. Il riuso di socket inattivi fra livelli di concorrenza
  poteva incrociare il timeout di keep-alive. Entrambi i lati del confronto finale
  aprono connessioni nuove per cella, mantenendo cookie, sessioni e contesto.
  Keep-alive resta attivo dentro la cella. Nessuna richiesta fallita viene
  ritentata dal generatore; gli errori continuano a far fallire il run.

Le regressioni amministrative storiche del 5 novembre non si riproducono nelle
prove isolate: nella prima matrice controllata i loro valori prima/dopo restano
vicini e con intervalli sovrapposti. Il vecchio carico misto a due worker aveva
servito tutte le richieste attraverso un solo PID; una ripetizione isolata sullo
stesso codice ha usato entrambi. Questi elementi spiegano perché il confronto
storico da solo non dimostra una regressione del codice su quei percorsi.

## Scalabilità separata a otto worker

Ulteriore prova sul codice finale: **36 celle, 56.801 richieste e zero
errori inattesi**, tre ripetizioni. Aumenta il numero dei processi; il guadagno di
parallelismo non è un miglioramento del codice a risorse applicative costanti.
Il confronto a quattro worker usa sei celle per punto; quello a otto ne usa tre.

| Percorso | Client | 4 worker req/s | 8 worker req/s | 4 worker p95 ms | 8 worker p95 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Home autenticata | 100 | 658.0 | 911.0 | 163.7 | 143.7 |
| Thread autenticato | 32 | 335.5 | 509.5 | 114.1 | 87.2 |
| Thread autenticato | 100 | 343.0 | 514.6 | 331.5 | 246.7 |
| Selettore trasferimenti | 1 | 220.8 | 187.0 | 4.7 | 6.1 |
| Pubblicazione e azioni | 10 | 382.5 | 471.7 | 42.6 | 39.3 |
| Carico misto | 10 | 364.8 | 467.9 | 53.0 | 36.6 |

Un primo avvio a otto worker è fallito prima di raccogliere celle, leggendo il PID
prima che il manager lo scrivesse. Il rerun usa l'attesa PID già presente nel
checkout corrente. [startup-pid.patch](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/startup-pid.patch) mostra l'unica differenza
del generatore rispetto alla matrice a quattro worker, interamente prima della
misura. Applicazione, connessioni per cella e carico misurato sono gli stessi.
La prova esplorativa precedente a otto worker resta nell'inventario e non alimenta
questa tabella. Risorse e distribuzioni per worker sono nei report originali;
RSS è una fotografia che può contare pagine condivise più volte, non un picco.
A otto worker il p99 del thread a 100 client è 290,5 ms (275,6–299,2), con risorse
applicative maggiori. Questa prova non dimostra la risoluzione del p99 a quattro
worker.

## Metodo e limiti

Apple M4, 10 core, 16 GiB; generatore, applicazione e PostgreSQL sulla stessa
macchina. Versioni, impostazioni e fixture sono registrate nei JSON e verificate
uguali fra i quattro lati: 240 thread, 4.800 post iniziali e 103 utenti di fixture.
HTTP/TCP locale con EV nativo, niente proxy/TLS/WAN o caricamento degli asset del
browser. Concorrenza 1/10/32/100, 100 letture seriali, dieci warmup, celle concorrenti
di quattro secondi e tre ripetizioni. Non è un test completo di ogni rotta.

Il server mantiene 2.048 client per worker e lo stesso keep-alive di cinque secondi
nei due lati. La cache SSR normale è attiva e GlifiStore è disattivato. Il cluster
temporaneo mantiene max_connections=80, shared_buffers=128 MiB, work_mem=4 MiB,
jit=on e fsync/full_page_writes/synchronous_commit=on. Background delivery e
realtime sono disattivati; le quote sono innalzate soltanto nell'entrypoint di
benchmark, conservando i contatori PostgreSQL. I risultati misurano lavoro ammesso.
Nessun tuning PostgreSQL, pool aggiuntivo o cache di HTML autenticato è stato
introdotto per ottenere questi numeri. Non costituiscono un confronto con Discourse
o NodeBB su fixture equivalenti.

Il monitor ha escluso carichi concorrenti noti dal confronto finale. Restano i
limiti di una workstation condivisa e di ripetizioni brevi. CPU macOS è indicativa;
non deduciamo efficienza per core da quei contatori. I p95 a 100 client rimangono
distinti da quelli a 32: un obiettivo di latenza va riferito al carico scelto.

## Verifiche funzionali

Lo snapshot applicativo misurato supera **15 file e 6.898 test**, inclusi confronto
SQL differenziale, ruoli, revoche, workflow GUI, limiti di query, riuso del lavoro,
rendering e policy dei listener; il log è in
[runs/after-final-verify/run.log](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/runs/after-final-verify/run.log). Le verifiche
Perl::Critic sui file Perl modificati sono passate.

Nel checkout condiviso un successivo controllo di 19 file / 7.458 test ha avuto
tre fallimenti, tutti nel test dello snapshot SQL: erano nel frattempo arrivate
le migrazioni indipendenti 2042/2043. Le altre 18 suite sono passate. Dopo la
rigenerazione dal database migrato, con hash delle migrazioni verificati stabili,
[il test dello snapshot passa tutti gli otto controlli](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/runs/after-root-schema-final-verify/run.log).
Non abbiamo ripetuto le 18 suite già passate; i log del primo tentativo sono
conservati. Push e passkey del checkout condiviso non fanno parte degli snapshot
usati per misurare la capacità.

Il successivo [smoke test HTTP completo](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/runs/after-root-http-smoke-verify/run.log)
passa anche sul checkout condiviso, verificando l'isolamento delle connessioni,
login/CSRF, identità persistite e tutte le operazioni del profilo smoke. È una
verifica funzionale e non contribuisce ai dati di capacità delle tabelle.

La pausa temporanea dell'altra prova è stata rimossa e il suo helper ripristinato
al checksum originale, come registra
[il controllo di ripristino](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/resource-exclusivity-cleanup.json).

## Evidenze e riproduzione

- [Confronto completo JSON](comparison.json) e [CSV](comparison.csv)
- [Scalabilità JSON](scaling.json)
- [Inventario di tutti i tentativi](run-inventory.json), inclusi fallimenti e fasi intermedie
- [Manifesto dei sorgenti](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/source-manifest.json)
- [Patch applicativa misurata](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/application.patch) e [patch del generatore applicata a entrambi i lati](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/harness.patch)
- [Verifiche aggiunte](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/throughput-regressions/2026-11-06/verification.patch), completate dopo le misure di capacità
- [Checksum](SHA256SUMS)

Per ricostruire gli snapshot: partire dal commit indicato in due copie con le
dipendenze bloccate installate; applicare harness.patch a entrambe e application.patch
soltanto al candidato. I run.json conservano gli argomenti esatti. Il generatore
crea e distrugge esclusivamente il proprio cluster/database; rimuovere le variabili
GPFORUM_ e le impostazioni PG ereditate, usando una shell senza l'ambiente del servizio.
Una directory di output deve essere nuova. Una replica fallita va preservata e
analizzata, non sostituita silenziosamente.

`verification.patch` aggiunge i test e i metadati della migrazione del candidato,
senza cambiare il carico. Lo
snapshot SQL generato è escluso dagli hash dei sorgenti misurati: è stato
rigenerato dopo le prove; il bootstrap del benchmark usa le migrazioni SQL.

In ciascuno snapshot il comando misurato è il seguente; alternare baseline,
candidato, candidato, baseline usando directory nuove. La prova a otto worker
cambia soltanto il numero dei worker (oltre alla correzione di avvio documentata).

```sh
script/gpforum-carton exec script/benchmark-http-complete --output artifacts/repro-001 --workers 4 --iterations 100 --warmup 10 --duration 4 --repetitions 3 --concurrency 1,10,32,100 --deadline 900 --scenario member.home --scenario member.thread --scenario guest.thread --scenario moderator.transfers --scenario journey.publishing_community --scenario mixed
```

Per distribuire il codice seguire il normale [aggiornamento del ruolo SQL](../../../docs/ops/sql-api-role.md):
migrazione 2041, riallineamento dei grant al catalogo v4 e riavvio dei servizi.
Nessuna impostazione del database del forum in uso è stata cambiata dalla campagna.
