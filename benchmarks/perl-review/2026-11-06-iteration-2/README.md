# Revisione Perl, seconda iterazione · 6 novembre 2026

Questa iterazione parte dal candidato verificato della [prima revisione](../2026-11-06/README.md). Le due copie confrontate condividono 973 file di runtime e differiscono soltanto nei quattro moduli elencati sotto. Le funzionalità Web Push e passkey in lavorazione nel checkout condiviso sono escluse. Non è una certificazione di perfezione dell’intera base di codice.

## Correzioni

- **Realtime:** gli identificativi entrano nella deduplicazione solo dopo un broadcast riuscito. Un rifiuto strutturato o un’eccezione resta ritentabile; le vecchie voci FIFO di un tentativo fallito non possono cancellare il ricordo del ritentativo riuscito. Le consegne parziali mantengono la semantica esistente. Un’eccezione durante il reinvio dei badge conserva il flag del gap.
- **Allegati PostgreSQL:** un limite esplicito `undef` usa il valore standard di Mojo; le letture di zero byte non eseguono query e non sostituiscono il chunk già disponibile. Restano invariati intervalli HTTP, EOF e lettura dell’intero oggetto.
- **Cache dei link:** una sorgente troppo grande per il budget configurato viene analizzata senza espellere le voci riutilizzabili. Restano i limiti di memoria e le copie degli array restituiti.
- **Presentazione delle liste:** categorie, thread, risultati di ricerca e suggerimenti leggono le colonne richieste in blocco, come già avveniva per i post. Le colonne opzionali conservano i controlli di caricamento; i test coprono hash, righe delle funzioni e righe con solo `get_column`. Il cambiamento riduce le chiamate Perl ai getter, senza modificare query o autorizzazioni.

## Verifiche

La [suite generale](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/runs/unit/run.log) passa **688 file / 20.685 controlli**. Le integrazioni PostgreSQL interessate passano **8 file / 557 controlli**, nei gruppi [realtime e allegati](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/runs/integration/run.log) e [ricerca e HTTP](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/runs/integration-pages/run.log). Il secondo gruppo include sessioni HTTP reali e verifica contenuti nascosti. Non è stata ripetuta l’intera suite PostgreSQL della prima iterazione.

[Sintassi, perltidy, runtime e architettura](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/runs/static/run.log) passano sull’intero snapshot; [Perl::Critic](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/runs/critic-final/run.log) passa sui nove file modificati. I [test mirati](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/runs/focused-final/run.log) passano 483 controlli. Gli stessi nuovi test [falliscono sul codice precedente](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/runs/baseline-red-final/run.log), riproducendo i difetti e il lavoro ripetuto.

Gli avvii intermedi sono conservati: il primo nuovo test degli allegati ometteva lo schema richiesto dalla fixture; la fixture corretta riproduce poi i cinque fallimenti attesi. Il primo controllo Critic ha richiesto tre adeguamenti di stile, risolti prima delle verifiche finali.

## Misure finali

Tutte le misure comparative seguono implementazione e verifiche. Ordine **prima/dopo/dopo/prima**, tre batch per caso e avvio: sei campioni per lato nei microbenchmark. Tempi monotoni, stesso interprete e dipendenze. I risultati sono operazioni Perl al secondo; intervalli min–max osservati, senza pretesa di significatività statistica.

| Caso | Prima op/s | Dopo op/s | Variazione mediana | Intervalli sovrapposti |
|---|---:|---:|---:|---|
| `projection_autocomplete_suggestion_function_row` | 159,798 | 278,506 | +74.29% | no |
| `projection_autocomplete_suggestion_hash` | 259,543 | 460,787 | +77.54% | no |
| `projection_category_function_row` | 145,579 | 177,913 | +22.21% | no |
| `projection_category_hash` | 279,930 | 383,970 | +37.17% | no |
| `projection_search_result_function_row` | 90,291 | 145,243 | +60.86% | no |
| `projection_search_result_hash` | 153,722 | 261,997 | +70.44% | no |
| `projection_thread_function_row` | 65,813 | 85,662 | +30.16% | no |
| `projection_thread_hash` | 120,226 | 177,303 | +47.48% | no |
| `realtime_duplicate_stub_no_io` | 952,787 | 1,167,563 | +22.54% | no |
| `realtime_success_stub_no_io` | 211,074 | 213,325 | +1.07% | sì |
| `source_hit_default` | 953,689 | 958,484 | +0.50% | sì |
| `source_mixed_small_budget` | 67,017 | 324,391 | +384.04% | no |

Il caso `source_mixed_small_budget` usa un budget esplicito di 1.024 caratteri e alterna una voce non memorizzabile a una sorgente calda: non descrive il budget predefinito. I casi realtime usano un hub senza I/O; non misurano PostgreSQL né WebSocket. Le differenze misurate e gli intervalli completi sono in [summary.json](summary.json).

## Confronto HTTP

Apple M4, 10 core, 16 GiB; quattro worker, PostgreSQL temporaneo con durabilità attiva, dataset e harness identici. Client asincroni Mojo con sessioni reali, due ripetizioni per avvio. A concorrenza 1 ogni cella esegue 40 richieste; a concorrenza 32 home e ricerca durano tre secondi. La categoria è misurata solo in seriale. Questi risultati non sono intercambiabili con `wrk`. Il solo entrypoint di benchmark alza le quote di ammissione, mantenendo i contatori PostgreSQL e i controlli applicativi. Listener realtime e Minion sono disattivati, come nel confronto precedente.

**40 celle, 25,538 richieste, 0 risposte non valide.** Ogni avvio osserva tutti e quattro i worker; tutte le celle previste sono presenti, senza errori o scenari saltati. RSS e CPU, con il metodo di rilevamento del sistema, rimangono nei report grezzi e nel riepilogo quando disponibili.

| Percorso | Client | Prima req/s | Dopo req/s | Variazione mediana | p95 prima → dopo, ms | Intervalli req/s sovrapposti |
|---|---:|---:|---:|---:|---:|---|
| member.category | 1 | 143.27 | 142.48 | -0.55% | 7.02 → 7.38 | sì |
| member.home | 1 | 162.05 | 161.29 | -0.47% | 6.40 → 6.33 | sì |
| member.home | 32 | 669.83 | 660.00 | -1.47% | 54.87 → 56.90 | sì |
| member.search | 1 | 90.97 | 91.72 | +0.83% | 11.53 → 11.41 | sì |
| member.search | 32 | 340.81 | 340.24 | -0.17% | 98.42 → 98.17 | sì |

Le percentuali sono descrittive di questi campioni brevi. Non dimostrano una capacità sostenuta, un aumento generale del throughput del sito o il rispetto di un limite p99. I processi noti di test, compilazione e benchmark sono stati monitorati: nessuna contesa di questo tipo è stata rilevata nelle misure finali; il computer non era un laboratorio isolato.

## Sorgenti e riproduzione

Le patch [applicativa](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/application.patch) e [dei test](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/verification.patch) descrivono solo questa iterazione. [source-manifest.json](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/source-manifest.json) contiene hash prima/dopo dei 973 file di runtime, i percorsi e la provenienza della prima revisione; `source-before` e `source-after` conservano i nove file confrontati. I nuovi test sono presenti su entrambi i lati per dimostrare il fallimento prima della correzione. Il file nativo [bench.pl](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-2/bench.pl) si esegue dalla radice della copia da verificare con `script/gpforum-carton exec perl /percorso/bench.pl`. I `run.json` riportano ogni comando HTTP e di verifica, da rieseguire con nuove directory di output.

[SHA256SUMS](SHA256SUMS) verifica tutti gli artefatti di questa cartella. Il confronto conserva anche i costi e il rumore dei campioni; non modifica i risultati della prima revisione.
