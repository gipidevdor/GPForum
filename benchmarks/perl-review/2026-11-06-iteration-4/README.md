# Revisione Perl, quarta iterazione · 6 novembre 2026

Questa revisione corregge validatori della cache HTTP e controlli di ingresso della paginazione. La base del codice e dei test è il candidato verificato della [terza iterazione](../2026-11-06-iteration-3/README.md). Cambiano cinque moduli Perl e una sola impronta dell’inventario architetturale. Le funzionalità indipendenti Web Push e passkey in lavorazione nel checkout condiviso sono escluse dalle copie verificate.

## Correzioni

- **Precedenza dei validatori:** quando la richiesta contiene `If-None-Match`, una data `If-Modified-Since` non può prevalere su un ETag diverso. Una rappresentazione cambiata viene inviata con il suo corpo anziché validare erroneamente quella precedente con 304. La data rimane utilizzabile dai client che non inviano ETag. La regola è quella della [RFC 9110, §13.1.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-13.1.3).
- **Confronto e liste di ETag:** gli identificatori con lo stesso valore opaco coincidono con o senza prefisso `W/`, secondo la [RFC 9110, §13.1.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-13.1.2). Il parser conserva virgole e backslash nei valori quotati, gestisce i membri vuoti di una lista e rifiuta input malformato prima di produrre una corrispondenza. Questo parser più completo ha un costo misurato maggiore nei casi indicati sotto.
- **Cursori:** un decodificatore condiviso rifiuta input non scalare o oltre 128 caratteri prima di decodificarlo. Restano i controlli di timestamp, UUID, posizione e formato del lettore; timestamp con microsecondi e fuso completo e le vecchie forme false dei pin sono coperti dai test. Il piano delle categorie usa il pianificatore comune per il limite, quindi decodifica il proprio cursore solo nel formato a tre parti: da due decodifiche a una.
- **Limiti:** ricerca e categorie richiedono cifre ASCII prima delle operazioni numeriche. Una combinazione come `1١` poteva produrre warning e, nella ricerca, finire ancora testuale nel parametro SQL intero; ora usa il valore predefinito. I tetti esistenti rimangono invariati.

## Verifiche

La [suite generale](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/unit-final/run.log) passa **691 file / 20.699 controlli**. Le [integrazioni PostgreSQL/HTTP](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/integration-final/run.log) passano **5 file / 654 controlli**, incluse richieste GET e HEAD condizionali reali, revoca delle pagine pubbliche e confronto esatto fra Function API e ORM per forum e ricerca. I [test mirati finali](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/focused-final/run.log) passano 420 controlli. Gli [stessi nuovi casi sul codice precedente](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/baseline-red-final/run.log) riproducono i difetti.

[Sintassi, perltidy, runtime e architettura finali](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/static-canonical/run.log) passano; [Perl::Critic](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/critic-final/run.log) passa sugli otto file Perl modificati. Il primo passaggio di stile ha richiesto soltanto nomi distinti e una catena di chiamate più corta nei test; il log rimane conservato.

Il primo controllo architetturale ha segnalato l’impronta del costruttore ORM storico `category_threads_resultset`. La revisione del suo diff conferma che cambia soltanto il pianificatore predefinito: query, colonne e binding restano gli stessi. È stata aggiornata solo quella impronta, mantenendo **178 voci / 186 occorrenze**, senza aggiungere accessi ORM o cambiare le policy. La [revisione](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/architecture-review.json), il primo [rilievo](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/static-final/run.log) e il [controllo finale](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/runs/architecture-final/run.log) sono conservati.

## Misure finali e ambiti dei confronti

I microbenchmark confrontano **terza → quarta iterazione**, isolando le modifiche di questa revisione. La campagna HTTP confronta invece **seconda → quarta iterazione**, prima della modifica alla home: verifica l’effetto cumulativo delle ultime due revisioni e ricontrolla la latenza osservata nella terza. I due confronti hanno manifesti distinti; un risultato HTTP non viene attribuito soltanto al nuovo parser o alla quarta revisione.

Tutte le misure comparative seguono implementazione e verifiche. Ordine **prima/dopo/dopo/prima**, tre batch per caso e avvio: sei campioni per lato nei microbenchmark. Stesso interprete, dipendenze e dati, tempi monotoni. Validatori e piani sono eseguiti senza DB o rete; non sono richieste HTTP al secondo. Tutti gli input cronometrati hanno lo stesso risultato semantico prima/dopo; i nuovi casi di correttezza con esito diverso sono verificati dai test.

| Caso | Prima operazioni/s | Dopo operazioni/s | Variazione mediana | Intervalli sovrapposti |
|---|---:|---:|---:|---|
| `category_call_no_cursor_no_database` | 232,171 | 220,080 | -5.21% | no |
| `category_call_pinned_cursor_no_database` | 73,353 | 78,233 | +6.65% | no |
| `etag_exact_weak` | 845,505 | 705,666 | -16.54% | no |
| `etag_list_eight_members` | 221,478 | 133,102 | -39.90% | no |
| `etag_wildcard` | 919,999 | 624,771 | -32.09% | no |
| `ordinary_plan_no_cursor` | 828,894 | 835,899 | +0.85% | sì |
| `ordinary_plan_oversized_4096` | 109,474 | 710,850 | +549.33% | no |
| `ordinary_plan_timestamp_cursor` | 146,340 | 138,032 | -5.68% | no |
| `stale_etag_with_older_date` | 112,563 | 220,148 | +95.58% | no |

Il parser conforme è più lento del confronto precedente su ETag esatto, wildcard e liste: il costo va mantenuto nel bilancio, non presentato come un guadagno generale. In tempo per chiamata, il caso esatto passa da 1,183 a 1,417 µs, il wildcard da 1,087 a 1,601 µs e la lista di otto membri da 4,515 a 7,513 µs. Il piano delle categorie senza cursore paga il passaggio al pianificatore dedicato, da 4,307 a 4,544 µs; con cursore evita invece la doppia decodifica. Anche il normale cursore timestamp paga il controllo di dimensione, da 6,833 a 7,245 µs. La risposta priva di cursore rimane un controllo separato. La gestione del cursore non valido di 4.096 caratteri è un limite di risorse, non una misura della navigazione normale. Gli intervalli completi sono in [summary.json](summary.json).

## HTTP cumulativo e latenza della home

Apple M4, 10 core, 16 GiB, quattro worker, PostgreSQL temporaneo con durabilità attiva e dati identici. Client asincroni Mojo con sessioni reali, due ripetizioni per avvio, 40 richieste nelle celle seriali. Le celle home e ricerca con 32 client durano **sei secondi**, il doppio della prova precedente. La categoria rimane un controllo seriale. La durata diversa richiede di usare questo confronto abbinato, anziché mescolare le sue celle con quelle vecchie.

Il solo entrypoint del banco di prova alza le quote di ammissione mantenendo i contatori PostgreSQL e i controlli applicativi. Listener realtime e Minion sono disattivati su entrambi i lati. Questi risultati non sono intercambiabili con `wrk`; i casi di ETag condizionale sono verificati nelle integrazioni, non rappresentati dalle richieste member di questa campagna.

**40 celle, 49,634 richieste, 0 risposte non valide.** Tutti i worker sono osservati e tutte le celle previste sono presenti; nessun errore o scenario saltato. RSS e CPU, quando disponibili e con il metodo indicato dal sistema, rimangono nei report grezzi.

| Percorso | Client | Prima req/s | Dopo req/s | Variazione mediana | p95 prima → dopo, ms | Intervalli req/s sovrapposti |
|---|---:|---:|---:|---:|---:|---|
| member.category | 1 | 142.66 | 142.61 | -0.03% | 7.31 → 7.21 | sì |
| member.home | 1 | 160.19 | 163.01 | +1.76% | 6.49 → 6.27 | sì |
| member.home | 32 | 648.50 | 659.56 | +1.71% | 61.75 → 60.41 | sì |
| member.search | 1 | 91.21 | 92.16 | +1.04% | 11.61 → 11.33 | sì |
| member.search | 32 | 340.12 | 343.04 | +0.86% | 98.60 → 97.56 | sì |

Sulla home con 32 client il p95 mediano passa da **61.75 a 60.41 ms**, il p99 da **84.23 a 79.49 ms**. Intervalli p95 sovrapposti: sì; p99: sì. Questo confronto più lungo non riproduce necessariamente l’aumento visto nei campioni precedenti, ma non certifica un miglioramento delle code né un limite p99. Il riepilogo conserva ciascun intervallo.

Le percentuali sono descrittive di questi campioni locali. I processi noti di test, compilazione e benchmark sono stati monitorati senza rilevare contesa nelle misure finali; il computer non era un laboratorio isolato. Non viene stabilito un aumento generale della capacità del sito.

## Artefatti

[Patch applicativa e impronta revisionata](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/application.patch), [patch dei test](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/verification.patch), [manifesto delle sorgenti](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/source-manifest.json), [benchmark Perl](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-4/bench.pl), copie dei nove file revisionati in `source-before` e `source-after`. `http-source-before` e `http-source-after` conservano gli otto file che differiscono nel confronto cumulativo; il manifesto contiene gli hash di tutti i 973 file di runtime per i tre stati.

Per ricostruire il lato HTTP corrente dalla seconda iterazione si applicano la patch applicativa della terza e quella di questa revisione. I microbenchmark partono invece dalla terza. Il file nativo `bench.pl` si esegue dalla radice della copia desiderata con `script/gpforum-carton exec perl /percorso/bench.pl`. I `run.json` riportano ogni comando e lo stato delle sorgenti; utilizzare directory di output nuove. [SHA256SUMS](SHA256SUMS) verifica gli artefatti senza modificare quelli delle revisioni precedenti.
