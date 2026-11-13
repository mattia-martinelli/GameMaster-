# Retro-Archive Manager

Gestore Bash per importare giochi da una cartella sorgente in un archivio organizzato per console. Il menu principale e' in sviluppo: al momento e' operativo soprattutto **Smart Ingest**; Deploy e Vault/Backup sono segnaposto.

## Requisiti

E' pensato per Linux o WSL con Bash e utility GNU (`find`, `sort`, `rsync`). Servono inoltre:

- `jq` per leggere il mapping e `archive_schema.json`;
- `fzf` per assegnare elementi non riconosciuti a una console;
- `rsync` per copiare o spostare i file.

Su Ubuntu/WSL:

```bash
sudo apt update
sudo apt install -y jq fzf rsync
```

Il generatore di fixture usa Bash e utility comuni, non richiede `jq`, `fzf` o `rsync`.

## Avvio

Apri Ubuntu/WSL e raggiungi la cartella del progetto. Se si trova sul disco C:, da WSL il percorso inizia con `/mnt/c/`.

```bash
cd /path/to/gamemanager_windows/GameManager
bash gamemanager.sh
```

Al primo avvio, se `ambiente.env` manca, il bootstrap guida la configurazione. Il file contiene percorsi locali e non va condiviso senza averli controllati.

Le variabili principali sono:

- `PATH_ARCHIVIO`: destinazione dell'archivio;
- `PATH_SHARE_ROOT`: radice della partizione del sistema (per esempio Batocera);
- `PATH_ROMS`: cartella `roms` da cui il bootstrap ricava le console;
- `SYSTEM_TARGET_NAME`: nome usato per il file mapping `${SYSTEM_TARGET_NAME}2archive.json`.

Prima di avviare un'operazione, verifica che i percorsi esistano e puntino ai dati corretti. Il bootstrap genera il mapping JSON dalle directory presenti in `PATH_ROMS` quando il mapping non esiste.

## Smart Ingest

Dal menu scegli `1) Smart Ingest`, poi inserisci il percorso della cartella da analizzare. Per percorsi con spazi, racchiudi il path tra virgolette.

L'ingest esamina solo gli elementi al primo livello della sorgente:

- le cartelle che corrispondono al mapping vengono assegnate alla console corrispondente;
- per le console definite in `archive_schema.json`, trasferisce solo file con estensioni dichiarate nello schema, includendo le sottocartelle;
- file sciolti e cartelle non riconosciute vengono proposti per classificazione; le estensioni possono suggerire una o piu' console, ma la scelta resta manuale;
- file sciolti con estensioni non previste vengono ignorati;
- console presenti nel mapping ma assenti dallo schema non hanno il filtro per estensione.

Scegli **Dry-Run** (`2`) per vedere il piano senza trasferire file. In modalita' reale, l'impostazione predefinita e' lo spostamento; e' possibile scegliere la copia. Lo spostamento puo' rimuovere i file dalla sorgente e cancellare directory rimaste vuote. Controlla sempre sorgente e destinazione prima di confermare.

## Generare una Sandbox

Il generatore crea file vuoti (0 byte), directory di sorgente/archivio simulate, un ambiente isolato e un `manifest.txt`. Non opera sui percorsi configurati nel progetto. Usa una cartella temporanea dedicata:

```bash
bash tools/gen_fixtures.sh --seed 7 --size small --out /tmp/gm-fixture
```

Dimensioni disponibili: `small`, `medium`, `large`. Usare lo stesso seed e la stessa dimensione riproduce lo stesso scenario. Se ometti `--out`, il generatore crea una cartella temporanea e stampa i comandi per usarla.

Per provare l'interfaccia copiata nella sandbox:

```bash
cd /tmp/gm-fixture/scripts
bash gamemanager.sh
```

Scegli Smart Ingest, usa come sorgente `/tmp/gm-fixture/Download Giochi` e seleziona Dry-Run. `fzf` viene usato per gli elementi da classificare. Il manifest descrive gli esiti attesi, ma al momento non esiste ancora un validatore automatico.

Quando hai finito, chiudi l'applicazione e rimuovi la sandbox indicando la cartella precisa creata dal generatore:

```bash
bash /path/to/gamemanager_windows/GameManager/tools/gen_fixtures.sh --clean /tmp/gm-fixture
```

Il comando di pulizia richiede il marcatore `.gm-fixture` presente nella sandbox. Non passare cartelle generiche o percorsi non creati dal generatore.

## Controllo Sintassi

Dalla cartella `GameManager/`:

```bash
bash -n gamemanager.sh bootstrap.sh ingest.sh OLD_script_games.sh tools/gen_fixtures.sh
```

Questo controlla la sintassi Bash, non il comportamento dell'importazione. Per quest'ultimo usare la sandbox; non testare operazioni di trasferimento sui dati reali.
