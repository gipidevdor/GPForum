# Dettaglio dei tempi · campagna del 2 novembre 2026

Revisione applicativa c7999c31, Apple M4 con 16 GiB. Tutte le latenze nelle tabelle sono in millisecondi; 1.000 ms = 1 secondo. Sono misure HTTP locali, con generatore, server e PostgreSQL sulla stessa macchina, senza rendering del browser o caricamento dei servizi terzi.

- p50: mediana; p95 e p99: percentili empirici della cella o dell'operazione indicata.
- N: richieste misurate, escludendo warmup e setup.
- Per pagine e carico concorrente: mediana dei tre percentili per cella; non percentile di campioni uniti.
- Per le operazioni dei percorsi: percentili del gruppo di campioni dell'operazione, che può includere percorsi e carichi differenti.
- SQL è già incluso nel tempo applicativo. Le mediane delle componenti non si sommano necessariamente.
- Con pochi campioni le stime della coda sono indicative; gli archivi hanno 20 richieste per ripetizione, i salvataggi serializzati soltanto sei campioni complessivi.

## Tutte le letture a singolo client, due processi server

### Pagine pubbliche

| Scenario | N | p50 | p95 | p99 | App p50 | SQL p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `guest.atom` | 300 | 2,8 | 5,1 | 6,4 | 1,5 | 0,4 |
| `guest.autocomplete` | 300 | 5,0 | 7,6 | 8,0 | 3,6 | 1,7 |
| `guest.categories` | 300 | 2,0 | 3,2 | 4,0 | 0,8 | 0,1 |
| `guest.category` | 300 | 2,1 | 2,4 | 2,9 | 0,8 | 0,1 |
| `guest.category_archive` | 60 | 253,4 | 260,3 | 260,3 | 250,2 | 15,2 |
| `guest.cookies` | 300 | 3,0 | 3,6 | 3,8 | 1,8 | 0,1 |
| `guest.health` | 300 | 22,4 | 23,8 | 25,3 | 19,6 | 0,3 |
| `guest.health_live` | 300 | 1,3 | 1,5 | 1,6 | 0,3 | 0,0 |
| `guest.health_ready` | 300 | 40,7 | 43,9 | 45,5 | 38,0 | 0,9 |
| `guest.home` | 300 | 6,2 | 8,6 | 9,7 | 4,5 | 0,6 |
| `guest.keys` | 300 | 1,4 | 1,7 | 1,9 | 0,4 | 0,1 |
| `guest.login` | 300 | 2,7 | 3,3 | 3,9 | 1,5 | 0,1 |
| `guest.password_reset` | 300 | 2,8 | 4,3 | 4,5 | 1,5 | 0,1 |
| `guest.privacy_policy` | 300 | 3,1 | 3,5 | 3,9 | 1,8 | 0,1 |
| `guest.profile` | 300 | 8,8 | 10,0 | 10,5 | 7,2 | 3,7 |
| `guest.register` | 300 | 2,8 | 3,7 | 4,2 | 1,6 | 0,1 |
| `guest.robots` | 300 | 1,5 | 2,7 | 3,6 | 0,2 | 0,0 |
| `guest.search` | 300 | 12,3 | 16,1 | 17,5 | 10,3 | 4,6 |
| `guest.signature` | 300 | 6,5 | 7,1 | 7,7 | 5,2 | 3,9 |
| `guest.sitemap` | 300 | 1,4 | 1,7 | 2,0 | 0,4 | 0,1 |
| `guest.sitemap_page` | 300 | 2,0 | 2,3 | 2,6 | 0,8 | 0,1 |
| `guest.tags` | 300 | 2,1 | 2,7 | 3,5 | 0,8 | 0,1 |
| `guest.terms` | 300 | 3,0 | 4,3 | 4,7 | 1,8 | 0,1 |
| `guest.thread` | 300 | 2,1 | 2,6 | 2,9 | 0,8 | 0,1 |
| `guest.thread_archive` | 60 | 11,6 | 12,3 | 12,3 | 10,3 | 0,7 |

### Utente autenticato

| Scenario | N | p50 | p95 | p99 | App p50 | SQL p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `member.autocomplete` | 300 | 9,5 | 11,4 | 12,3 | 6,9 | 3,2 |
| `member.avatar` | 300 | 6,3 | 7,9 | 8,4 | 3,8 | 0,6 |
| `member.bookmarks` | 300 | 11,3 | 12,8 | 13,3 | 8,6 | 4,9 |
| `member.categories` | 300 | 5,1 | 6,1 | 6,6 | 3,3 | 0,5 |
| `member.category` | 300 | 8,6 | 9,5 | 10,1 | 6,6 | 1,4 |
| `member.drafts` | 300 | 8,4 | 9,8 | 10,2 | 5,7 | 1,1 |
| `member.feed` | 300 | 12,1 | 16,5 | 27,7 | 8,6 | 3,8 |
| `member.home` | 300 | 7,4 | 8,7 | 9,9 | 5,6 | 1,1 |
| `member.mentions` | 300 | 8,7 | 10,1 | 10,4 | 6,1 | 2,7 |
| `member.message_compose` | 300 | 3,8 | 6,1 | 7,3 | 2,2 | 0,3 |
| `member.messages` | 300 | 3,8 | 5,0 | 5,9 | 2,2 | 0,3 |
| `member.new_thread` | 300 | 7,4 | 8,6 | 8,9 | 4,7 | 0,7 |
| `member.notification_summary` | 300 | 5,5 | 6,8 | 7,3 | 3,3 | 1,1 |
| `member.notifications` | 300 | 7,3 | 12,2 | 13,5 | 5,0 | 1,1 |
| `member.pending` | 300 | 8,2 | 9,7 | 10,1 | 5,6 | 1,2 |
| `member.privacy` | 300 | 4,1 | 4,9 | 5,8 | 2,5 | 0,4 |
| `member.relations` | 300 | 3,6 | 4,4 | 5,2 | 2,1 | 0,3 |
| `member.search` | 300 | 15,4 | 17,9 | 19,1 | 12,6 | 5,2 |
| `member.security` | 300 | 5,6 | 7,3 | 7,7 | 3,2 | 0,6 |
| `member.settings` | 300 | 8,3 | 10,0 | 10,1 | 5,4 | 0,8 |
| `member.thread` | 300 | 15,1 | 20,2 | 21,0 | 12,1 | 1,5 |

### Moderazione

| Scenario | N | p50 | p95 | p99 | App p50 | SQL p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `moderator.actions` | 300 | 16,9 | 22,4 | 24,4 | 13,9 | 0,9 |
| `moderator.reports` | 300 | 20,5 | 23,9 | 25,7 | 17,2 | 0,9 |
| `moderator.review` | 300 | 3,7 | 5,1 | 6,2 | 2,3 | 0,4 |
| `moderator.suspensions` | 300 | 5,3 | 8,5 | 8,9 | 3,3 | 0,6 |
| `moderator.transfers` | 300 | 3,7 | 4,2 | 5,1 | 2,2 | 0,4 |

### Amministrazione

| Scenario | N | p50 | p95 | p99 | App p50 | SQL p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `admin.address-bans` | 300 | 4,0 | 4,7 | 5,1 | 2,6 | 0,4 |
| `admin.announcements` | 300 | 3,6 | 4,2 | 4,8 | 2,2 | 0,4 |
| `admin.audit` | 300 | 12,7 | 13,4 | 13,7 | 10,6 | 0,9 |
| `admin.automod` | 300 | 3,9 | 4,6 | 5,2 | 2,5 | 0,5 |
| `admin.categories` | 300 | 4,6 | 5,1 | 5,5 | 3,0 | 0,4 |
| `admin.configuration` | 300 | 5,3 | 6,6 | 7,3 | 3,6 | 0,4 |
| `admin.dashboard` | 300 | 76,4 | 85,8 | 104,7 | 73,7 | 2,6 |
| `admin.integrations` | 300 | 4,5 | 5,4 | 6,1 | 3,0 | 1,0 |
| `admin.jobs` | 300 | 8,9 | 13,7 | 15,7 | 5,9 | 1,2 |
| `admin.metrics` | 300 | 33,5 | 35,4 | 36,5 | 31,0 | 0,8 |
| `admin.plugins` | 300 | 6,8 | 7,7 | 8,1 | 4,7 | 0,4 |
| `admin.privacy` | 300 | 4,3 | 5,1 | 5,9 | 2,7 | 0,5 |
| `admin.registration` | 300 | 3,7 | 4,4 | 4,8 | 2,3 | 0,5 |
| `admin.roles` | 300 | 5,6 | 6,2 | 6,8 | 3,9 | 0,5 |
| `admin.security` | 300 | 5,4 | 6,2 | 6,6 | 3,6 | 0,9 |
| `admin.settings` | 300 | 6,9 | 8,0 | 8,3 | 5,0 | 0,9 |
| `admin.status` | 300 | 75,1 | 79,6 | 84,9 | 72,3 | 1,9 |
| `admin.user_roles` | 300 | 4,8 | 6,3 | 7,5 | 3,2 | 0,7 |
| `admin.users` | 300 | 13,7 | 14,6 | 14,9 | 11,7 | 0,7 |

## Pagine autenticate sotto carico

Il profilo a quattro processi è il rerun completo senza risposte inattese. Il primo tentativo con un errore TCP è conservato separatamente nel rapporto principale.

### 2 processi server

| Pagina | Sessioni | N | p50 | p95 | p99 | Intervallo dei p95 fra ripetizioni |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Home | 1 | 300 | 7,4 | 8,7 | 9,9 | 7,9–9,1 |
| Home | 10 | 4330 | 48,4 | 57,1 | 70,4 | 56,0–60,5 |
| Home | 50 | 4328 | 121,5 | 276,5 | 365,4 | 270,1–292,9 |
| Home | 100 | 4208 | 227,5 | 820,9 | 991,8 | 570,3–829,0 |
| Discussioni | 1 | 300 | 15,1 | 20,2 | 21,0 | 15,0–20,4 |
| Discussioni | 10 | 2062 | 82,4 | 118,0 | 129,3 | 97,4–125,5 |
| Discussioni | 50 | 2191 | 365,2 | 516,8 | 709,2 | 443,4–562,0 |
| Discussioni | 100 | 2033 | 680,2 | 1403,1 | 1617,2 | 969,3–1801,5 |
| Ricerca | 1 | 300 | 15,4 | 17,9 | 19,1 | 16,2–22,4 |
| Ricerca | 10 | 1942 | 77,6 | 133,5 | 198,4 | 125,3–135,1 |
| Ricerca | 50 | 1853 | 413,2 | 661,7 | 791,7 | 522,3–812,6 |
| Ricerca | 100 | 2193 | 470,0 | 1596,8 | 1718,5 | 1493,4–1647,3 |
| Notifiche | 1 | 300 | 7,3 | 12,2 | 13,5 | 6,5–13,8 |
| Notifiche | 10 | 3997 | 28,2 | 83,0 | 117,5 | 53,9–89,2 |
| Notifiche | 50 | 3956 | 131,8 | 403,3 | 565,2 | 246,4–448,0 |
| Notifiche | 100 | 4799 | 302,5 | 555,0 | 816,7 | 455,7–689,9 |

### 4 processi server

| Pagina | Sessioni | N | p50 | p95 | p99 | Intervallo dei p95 fra ripetizioni |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Home | 1 | 300 | 7,8 | 10,5 | 11,2 | 7,9–10,8 |
| Home | 10 | 5437 | 25,9 | 47,4 | 61,4 | 39,9–51,7 |
| Home | 50 | 6681 | 76,4 | 290,2 | 334,9 | 170,7–310,5 |
| Home | 100 | 6964 | 162,0 | 329,8 | 443,2 | 299,6–917,6 |
| Discussioni | 1 | 300 | 15,9 | 18,7 | 20,7 | 16,3–21,5 |
| Discussioni | 10 | 2492 | 52,0 | 106,5 | 159,4 | 104,7–131,2 |
| Discussioni | 50 | 3195 | 201,6 | 515,3 | 768,0 | 497,3–595,1 |
| Discussioni | 100 | 3595 | 400,5 | 723,3 | 1104,2 | 699,2–747,5 |
| Ricerca | 1 | 300 | 12,3 | 13,6 | 14,2 | 12,4–13,7 |
| Ricerca | 10 | 3151 | 37,7 | 67,0 | 110,5 | 63,8–150,9 |
| Ricerca | 50 | 3693 | 196,5 | 388,8 | 537,2 | 287,9–526,5 |
| Ricerca | 100 | 3835 | 327,9 | 903,4 | 1512,6 | 820,4–1294,2 |
| Notifiche | 1 | 300 | 13,7 | 17,8 | 18,8 | 15,0–21,3 |
| Notifiche | 10 | 3462 | 37,8 | 77,7 | 107,9 | 68,8–82,3 |
| Notifiche | 50 | 4402 | 116,6 | 348,2 | 494,2 | 335,2–593,2 |
| Notifiche | 100 | 4412 | 282,1 | 782,5 | 1051,7 | 637,1–973,2 |

## Tempo del server e tempo osservato dal client

Qui tutte le colonne sono mediane dei p50 delle tre celle, a 100 sessioni. Il tempo esterno all'intervallo applicativo comprende attesa, scheduling, trasporto, consegna della risposta e costi del generatore: non misura soltanto la coda del server.

| Pagina | Processi | HTTP p50 | App p50 | SQL p50, incluso in App | Esterno ad App p50 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Home | 2 | 227,5 | 5,7 | 1,1 | 218,8 |
| Discussioni | 2 | 680,2 | 13,1 | 1,7 | 666,7 |
| Ricerca | 2 | 470,0 | 12,7 | 5,3 | 453,7 |
| Notifiche | 2 | 302,5 | 4,4 | 0,9 | 297,4 |
| Home | 4 | 162,0 | 6,1 | 1,0 | 154,9 |
| Discussioni | 4 | 400,5 | 14,4 | 1,8 | 387,2 |
| Ricerca | 4 | 327,9 | 12,8 | 5,3 | 315,5 |
| Notifiche | 4 | 282,1 | 9,2 | 2,1 | 271,7 |

## Plugin: prova del codice locale

Ogni operazione ha 60 richieste, nei percorsi con dieci sessioni amministrative concorrenti e due processi server. I tempi comprendono la risposta completa della pagina di prova; non isolano il solo resolver e non includono il player o il servizio esterno. La prova matematica misura la preparazione server della formula, non l'esecuzione di KaTeX nel browser.

| Plugin | N | HTTP p50 | HTTP p95 | HTTP p99 | App p50 | SQL p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| YouTube | 60 | 43,8 | 52,4 | 69,9 | 6,9 | 0,8 |
| GitHub | 60 | 41,2 | 45,6 | 66,1 | 6,5 | 0,8 |
| Facebook | 60 | 40,4 | 45,2 | 70,9 | 6,4 | 0,7 |
| Instagram | 60 | 41,4 | 45,5 | 65,6 | 6,6 | 0,8 |
| Spotify | 60 | 39,7 | 46,9 | 69,2 | 6,6 | 0,8 |
| Apple Music | 60 | 40,4 | 45,2 | 66,0 | 6,6 | 0,7 |
| Wikipedia | 60 | 41,7 | 46,0 | 72,2 | 6,8 | 0,7 |
| Vimeo | 60 | 41,1 | 46,5 | 67,4 | 6,6 | 0,7 |
| GitLab | 60 | 39,5 | 46,2 | 64,9 | 6,5 | 0,8 |
| Codeberg | 60 | 39,8 | 46,4 | 66,9 | 6,5 | 0,8 |
| Mastodon | 60 | 41,4 | 46,1 | 66,6 | 6,6 | 0,8 |
| PeerTube | 60 | 40,8 | 44,9 | 65,9 | 6,5 | 0,7 |
| Equazioni | 60 | 37,9 | 60,7 | 65,5 | 6,5 | 0,8 |

## Scritture e autenticazione

Aggregati d'operazione dei percorsi concorrenti con due processi server. I salvataggi di configurazione e i cambi di stato dei plugin sono serializzati; per i loro sei campioni si riporta il massimo, senza attribuire stabilità ai percentili di coda.

| Operazione | N | HTTP p50 | HTTP p95 | Massimo HTTP | App p50 | SQL p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Crea discussione | 120 | 78,9 | 104,0 | 106,2 | 7,6 | 3,2 |
| Pubblica risposta | 120 | 72,1 | 120,1 | 131,3 | 7,7 | 3,0 |
| Salva bozza | 60 | 39,2 | 47,4 | 53,9 | 3,2 | 1,0 |
| Anteprima testo | 60 | 39,0 | 55,3 | 66,2 | 3,2 | 0,9 |
| Anteprima integrazioni ed equazione | 60 | 47,5 | 63,8 | 69,1 | 3,7 | 0,7 |
| Avvia messaggio privato | 60 | 39,0 | 54,0 | 55,2 | 3,4 | 1,4 |
| Rispondi al messaggio | 60 | 34,6 | 46,9 | 47,7 | 3,3 | 1,3 |
| Mi piace | 60 | 43,3 | 48,0 | 48,7 | 3,8 | 1,6 |
| Reazione | 60 | 44,4 | 58,2 | 59,7 | 3,9 | 1,6 |
| Vota sondaggio | 60 | 33,6 | 45,9 | 50,0 | 3,6 | 1,7 |
| Verifica password/login | 30 | 418,9 | 655,8 | 664,5 | 80,6 | 1,9 |
| Logout | 30 | 40,1 | 98,1 | 113,3 | 6,4 | 1,4 |
| Salva impostazioni | 6 | 8,7 | pochi campioni | 11,0 | 6,7 | 1,9 |
| Abilita plugin | 6 | 6,1 | pochi campioni | 6,4 | 4,0 | 1,8 |
| Disabilita plugin | 6 | 6,1 | pochi campioni | 6,9 | 3,8 | 1,7 |

## Variabilità delle notifiche

La prova isolata con quattro processi e 100 sessioni registra p50 151,2, p95 247,6, p99 334,5. Questi valori sono distinti dal rerun dopo home, discussioni e ricerca; non sostituiscono i dati meno favorevoli.

## Confronto con il checkpoint precedente

Dataset medium e listener Unix, due processi server, 32 connessioni. Questi tempi non sono confrontabili in valore assoluto con il profilo HTTP completo; ogni colonna è la mediana di tre ripetizioni alternate.

| Pagina | Prima p50 | Misurata p50 | Prima p95 | Misurata p95 | Prima p99 | Misurata p99 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Home | 346,3 | 103,4 | 372,5 | 107,3 | 374,0 | 110,0 |
| Discussioni | 239,3 | 180,2 | 254,7 | 191,4 | 256,9 | 193,1 |
| Categoria | 106,7 | 83,8 | 108,3 | 85,3 | 109,1 | 85,8 |
| Ricerca | 197,6 | 176,8 | 199,7 | 185,8 | 208,4 | 191,4 |

## Outbox

1.000 messaggi per cella, trasporto no-op e PostgreSQL reale. Mediana di tre ripetizioni; durata espressa in millisecondi, migrazioni e seed esclusi. I percentili di batch non sono latenze end-to-end per messaggio.

| Worker | Durata di 1.000 messaggi | Batch p50 | Batch p95 | Batch p99 |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 512,0 | 47,8 | 52,1 | 52,1 |
| 2 | 335,8 | 67,3 | 68,3 | 69,1 |
| 4 | 338,1 | 59,2 | 66,8 | 69,0 |

## Durata delle prove

Durate delle campagne HTTP e diagnostiche, comprendenti il rispettivo setup. Sono distinte dalle latenze di una singola richiesta.

| Prova | Secondi | Minuti e secondi |
| --- | ---: | --- |
| full-workers2 | 491,8 | 8 min 11.8 s |
| hot-workers4-attempt1 | 213,8 | 3 min 33.8 s |
| hot-workers4-confirm | 221,5 | 3 min 41.5 s |
| notifications-workers4 | 62,5 | 1 min 2.5 s |
| Diagnostica, 150 file | 342,6 | 5 min 42.6 s |
| Supplemento HTTP | 17,8 | 0 min 17.8 s |

## Dati completi

- [Tutte le 158 operazioni: CSV con p50/p95/p99, massimo e componenti](operation-timings.csv)
- [Tutte le 114 combinazioni di scenario/carico: CSV](http-summary.csv)
- [JSON completo con celle, campioni e intervalli](full-workers2/http-complete.json)
- [Rapporto principale e limiti delle misure](README.md)
