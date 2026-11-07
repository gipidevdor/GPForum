# Revisione Perl, terza iterazione · 6 novembre 2026

La base del confronto è il candidato verificato della [seconda iterazione](../2026-11-06-iteration-2/README.md). Su 973 file di runtime, questa revisione modifica soltanto `Infrastructure::Row`, `HomePageReader` e `Search::Searcher`. Il lavoro indipendente su Web Push e passkey è escluso dalle copie verificate.

## Correzioni e riduzione del lavoro

- **Ricerca Unicode:** lo stesso pattern individua il punto del testo da mostrare ed evidenzia le corrispondenze. La ricerca senza distinzione di maiuscole può associare `STRASSE` a `Straße`; il precedente confronto con `lc` non gestiva le trasformazioni che cambiano lunghezza, perdendo sia evidenziazione sia posizione dello snippet. I nuovi test riproducono il difetto anche dopo la prima finestra del corpo.
- **Lavoro per pagina:** termini e pattern di evidenziazione sono preparati una volta per la pagina. La composizione HTML distingue direttamente le parti catturate dal pattern, senza ricontrollare ogni frammento contro tutti i termini. Ogni risultato conserva una propria copia di `highlight_terms`; le parti di testo continuano a essere escape prima di inserire i tag `mark`. Le pagine senza risultati non preparano il pattern.
- **Letture delle righe:** home, ricerca e autocomplete leggono le colonne richieste in blocco. Un adattatore condiviso gestisce hash, righe delle funzioni, righe ORM e adattatori con il solo `get_column`. Le colonne opzionali mantengono il controllo di caricamento e una mancanza restituisce un solo `undef`, anche in contesto lista. Le sonde di capacità ignorano eventuali override di `can` sulla riga.
- **Limiti della home:** solo interi ASCII positivi raggiungono i lettori, con tetto 50. Valori vuoti, frazionari, negativi o non numerici usano i valori predefiniti della home, senza warning di conversione e senza attivare per errore i limiti più grandi dei lettori sottostanti.

## Verifiche

La [suite generale finale](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/unit-final/run.log) passa **690 file / 20.693 controlli**. Le [integrazioni PostgreSQL/HTTP](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/integration-final/run.log) passano **7 file / 562 controlli**, inclusi ricerca di contenuti nascosti, ricerca ibrida, estratti della home e sessioni HTTP reali. Il confronto differenziale conserva la parità esatta fra Function API e ORM per ranking, ordine, limiti, snippet e metadati esistenti. Non è stata ripetuta l’intera suite PostgreSQL delle iterazioni precedenti.

[Sintassi e perltidy sui sei file modificati, runtime e architettura](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/static-final/run.log) passano. [Perl::Critic](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/critic-canonical/run.log) non rileva violazioni sui sei file. I [test mirati](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/focused-final/run.log) passano 405 controlli. I [nuovi test sul codice precedente](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/baseline-red-canonical/run.log) falliscono per Unicode, limiti e letture ripetute. Il conteggio dei getter sul caso di tre risultati scende da 43 a uno; quello della home di prova da 22 alle sole letture opzionali. Questi sono conteggi di chiamate Perl, non query SQL.

La prima integrazione ha respinto una proposta di restituire `source_thread_id`: il vecchio resultset ORM lo seleziona, ma la Function API attuale non lo restituisce. L’aggiunta è stata ritirata, insieme al solo nuovo test che la richiedeva; il contratto dei risultati e i test differenziali esistenti sono rimasti invariati. La [proposta verificata](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/metadata-contract-investigation/lib/GPForum/Service/Search/Searcher.pm) e il [run fallito](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/runs/integration/run.log) sono conservati. Un eventuale ampliamento di quel contratto richiede una revisione separata della Function API. Anche il primo rilievo di stile nel nuovo test è conservato e risolto prima dei controlli finali.

## Misure finali

Tutte le misure comparative sono state avviate dopo l’implementazione e i controlli finali. Ordine **prima/dopo/dopo/prima**, tre batch per caso in ogni avvio: sei campioni per lato. Tempi monotoni, stesso interprete, dipendenze e dati. Una operazione è un’intera chiamata di servizio Perl: **non** è una riga proiettata né una richiesta HTTP. I lettori della home e il livello delle funzioni SQL sono simulati senza I/O; il costo di preparazione, copia dei dati e composizione rimane incluso. Le autorizzazioni e il database reale sono coperti separatamente dalle integrazioni e dal confronto HTTP.

| Caso | Prima chiamate Perl/s | Dopo chiamate Perl/s | Variazione mediana | Intervalli sovrapposti |
|---|---:|---:|---:|---|
| `autocomplete_stub_no_database` | 3,953 | 6,968 | +76.24% | no |
| `home_hash_no_io` | 2,399 | 3,391 | +41.31% | no |
| `home_mixed_function_rows_no_io` | 2,021 | 2,758 | +36.49% | no |
| `ranked_search_eight_terms_stub_no_database` | 365 | 521 | +42.72% | no |
| `ranked_search_empty_stub_no_database` | 62,855 | 62,582 | -0.44% | sì |
| `ranked_search_one_term_stub_no_database` | 616 | 744 | +20.77% | no |

La home contiene 12 categorie e 20 thread; il caso misto usa categorie come hash e thread come righe delle funzioni. La ricerca ha 25 risultati, corpi di circa un KiB e uno oppure otto termini; un caso separato copre le risposte vuote. Gli intervalli min–max completi sono in [summary.json](summary.json): sono intervalli osservati, non intervalli di confidenza.

## Confronto HTTP

Apple M4, 10 core, 16 GiB, quattro worker. PostgreSQL temporaneo con durabilità attiva, dataset e harness identici. Client asincroni Mojo e sessioni reali: due ripetizioni per avvio, 40 richieste per cella seriale e tre secondi per cella con 32 client su home e ricerca. La categoria è un controllo seriale. I risultati non sono intercambiabili con `wrk`. Il solo entrypoint del banco di prova alza le quote di ammissione mantenendo i contatori PostgreSQL e i controlli applicativi; listener realtime e Minion sono disattivati su entrambi i lati.

**40 celle, 25,645 richieste, 0 risposte non valide.** Ogni avvio osserva i quattro worker, tutte le celle previste sono presenti e non ci sono errori o scenari saltati. RSS e CPU, con il metodo e i limiti di rilevamento del sistema, sono conservati nei report grezzi e nel riepilogo quando disponibili.

| Percorso | Client | Prima req/s | Dopo req/s | Variazione mediana | p95 prima → dopo, ms | Intervalli req/s sovrapposti |
|---|---:|---:|---:|---:|---:|---|
| member.category | 1 | 143.39 | 140.14 | -2.26% | 7.24 → 7.21 | sì |
| member.home | 1 | 159.57 | 163.07 | +2.20% | 6.49 → 6.36 | no |
| member.home | 32 | 666.97 | 670.43 | +0.52% | 53.39 → 58.34 | sì |
| member.search | 1 | 91.12 | 92.59 | +1.62% | 11.39 → 11.42 | sì |
| member.search | 32 | 341.72 | 345.89 | +1.22% | 97.84 → 97.71 | sì |

La home con 32 client ha p95 mediano da 53,39 a 58,34 ms e p99 da 63,95 a 73,28 ms. Gli intervalli osservati si sovrappongono per entrambi: il costo Perl inferiore non dimostra un miglioramento delle code di latenza HTTP, e questi campioni non escludono un peggioramento della coda. I dati completi rimangono nel riepilogo.

Le percentuali descrivono questi campioni brevi: non stabiliscono una capacità sostenuta, un incremento generale del throughput o un limite p99. Sono stati monitorati i processi noti di test, compilazione e benchmark; nessuna contesa di questo tipo è stata rilevata nelle misure finali. Il computer non era un laboratorio isolato.

## Artefatti riproducibili

[Patch applicativa](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/application.patch), [patch dei test](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/verification.patch), [manifesto delle sorgenti](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/source-manifest.json) con gli hash dei 973 file di runtime prima/dopo e le sei sorgenti interessate in `source-before` e `source-after`. Il manifesto identifica la provenienza della seconda iterazione. I test nuovi sono presenti sui due lati per riprodurre i fallimenti tramite i comandi dei `run.json`.

Il benchmark nativo [bench.pl](https://github.com/gipidevdor/GPForum/blob/2ade1f06b4ea65a591161551c00f9d6abca7b71b/benchmarks/perl-review/2026-11-06-iteration-3/bench.pl) si esegue dalla radice della copia da confrontare con `script/gpforum-carton exec perl /percorso/bench.pl`. I `run.json` conservano ogni comando HTTP e di verifica, da rieseguire con directory di output nuove. [SHA256SUMS](SHA256SUMS) copre gli artefatti di questa cartella; i risultati precedenti rimangono separati.
