# Piano di sviluppo

Questo piano distingue il lavoro gia' presente dalle decisioni gia' concordate e dalle idee ancora da definire. Le operazioni di prova vanno eseguite esclusivamente nella sandbox, mai sui percorsi reali configurati dall'utente.

## Stato attuale

- [x] Aggiungere suggerimenti di console basati su `accepted_extensions` in `archive_schema.json`.
- [x] Filtrare i file trasferiti nelle cartelle riconosciute o classificate, includendo le sottocartelle.
- [x] Creare `GameManager/tools/gen_fixtures.sh`: genera file vuoti, cartelle realistiche, ambiente isolato e manifest; supporta seed, dimensioni e pulizia con marcatore.
- [x] Usare Ubuntu/WSL come ambiente di lavoro Bash.
- [ ] Verificare il comportamento end-to-end di Smart Ingest nella sandbox. La sintassi Bash e' stata controllata, ma non equivale a un test funzionale.

## Prossimo passo concordato: validatore

Creare un validatore che confronti la sandbox dopo l'ingest con `manifest.txt`.

- Controllare file previsti, destinazioni e file esclusi dai filtri.
- Verificare che i duplicati non sovrascrivano quelli gia' in archivio.
- Controllare che il dry-run non modifichi sorgente o archivio.
- Provare copia e spostamento solo dentro la sandbox; nel caso di spostamento, verificare quali file restano nella sorgente.
- Gestire gli esiti che richiedono una scelta interattiva in `fzf`: mantenere `fzf` per ora e decidere in seguito come automatizzarli.
- Rendere i fallimenti leggibili e restituire un codice di uscita non-zero se le aspettative non sono rispettate.

**Criterio di completamento:** una prova ripetibile, identificata dal seed, termina con esito pass/fail chiaro e non tocca dati esterni alla sandbox.

## Stabilizzare Smart Ingest

Prima di aggiungere funzioni di trasferimento, correggere e testare i rischi individuati nel flusso attuale:

- Sostituire `eval` sull'input del percorso sorgente con una lettura sicura che supporti spazi e caratteri speciali.
- Controllare la presenza delle dipendenze prima di iniziare; non proseguire con classificazione incompleta se mancano `jq`, `fzf` o `rsync`.
- Verificare i codici di uscita di `rsync` e mostrare successo solo per gli elementi trasferiti correttamente.
- Limitare la rimozione delle directory vuote agli elementi effettivamente coinvolti nello spostamento.
- Validare mapping e destinazioni, senza permettere che il percorso risultante esca da `PATH_ARCHIVIO`.

Questi interventi non sono ancora implementati. Prima di ogni modifica, aggiungere al validatore un caso che dimostri il problema e la correzione attesa.

## Configurazione e dipendenze

### Configurazione

- `ambiente.env` resta il file principale per modificare i percorsi.
- Rendere il bootstrap piu' chiaro nel validare archivio, radice SHARE e cartella ROMS.
- Evitare `eval` anche negli input del bootstrap.
- Non sovrascrivere configurazione esistente senza conferma esplicita.

### Dipendenze

Ridurre le dipendenze solo dopo aver fissato il comportamento con i test:

1. Valutare un menu numerato Bash al posto di `fzf`; la sostituzione e' rimandata e non approvata per ora.
2. Valutare come leggere mapping e schema senza `jq` oppure se mantenerlo.
3. Tenere `rsync` finche' copia, spostamento, filtri e gestione dei duplicati non hanno test affidabili; solo allora valutare un'alternativa.

## Funzioni ancora da realizzare

### Deploy a sistema

Il menu lo descrive come invio di giochi dall'archivio al sistema (ad esempio Batocera). Prima di implementarlo, definire:

- come selezionare console e giochi;
- se il deploy copia o sposta (proposta iniziale: copia);
- comportamento in caso di file gia' esistenti;
- quali dati del `archive_schema.json` applicare.

### Vault & Backup

Il menu lo descrive come backup della partizione SHARE ed export dell'archivio. Prima di implementarlo, definire:

- quali cartelle includere (ROM, BIOS, salvataggi o configurazione);
- destinazione e struttura del backup;
- comportamento per backup esistenti e spazio insufficiente;
- se export e compressione sono operazioni separate.

`archive_schema.json` descrive gia' opzioni di compressione e salvataggi, ma queste non sono ancora usate dal manager. Non avviare conversioni o modifiche ai file originali senza una strategia e test dedicate.

## Fuori ambito per ora

- Non sostituire `fzf` prima di aver completato i test e concordato il nuovo flusso.
- Non modificare la vecchia implementazione `GameManager/OLD_script_games.sh`, salvo richiesta specifica.
- Non testare ingest, deploy, backup o pulizia sui dati reali.
