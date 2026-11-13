#!/bin/bash

# ==============================================================================
# MODULI CORE: SMART INGEST ("Lo smistatore di monnezza")
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/ambiente.env"

# Carica l'ambiente se esiste
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Errore: Ambiente non configurato. Esegui prima il bootstrap."
    exit 1
fi

# Palette Colori Cyberpunk
HEX_CYAN="\033[1;36m"
HEX_PURPLE="\033[1;35m"
HEX_GREEN="\033[1;32m"
HEX_RED="\033[1;31m"
HEX_YELLOW="\033[1;33m"
HEX_BLUE="\033[1;34m"
HEX_RESET="\033[0m"

SCHEMA_FILE="$SCRIPT_DIR/archive_schema.json"

# Estensioni accettate da una console (archive_folder), una per riga.
schema_exts_for() {
    [ -f "$SCHEMA_FILE" ] || return 0
    jq -r --arg c "$1" '.systems[] | select(.archive_folder == $c) | .accepted_extensions[]' "$SCHEMA_FILE" 2>/dev/null
}

schema_all_exts() {
    [ -f "$SCHEMA_FILE" ] || return 0
    jq -r '[.systems[].accepted_extensions[]] | unique | .[]' "$SCHEMA_FILE" 2>/dev/null
}

# $1 = nome file, $2 = elenco estensioni (una per riga)
ext_in_list() {
    local name="${1##*/}" ext
    [[ "$name" == *.* ]] || return 1
    ext=".${name##*.}"
    grep -qxF -- "${ext,,}" <<< "$2"
}

# Console suggerite per un file o una cartella, ordinate per numero di estensioni compatibili.
suggest_consoles() {
    [ -f "$SCHEMA_FILE" ] || return 0
    local target="$1" exts_json
    if [ -d "$target" ]; then
        exts_json=$(find "$target" -type f -name '*.*' -printf '%f\n' | sed 's/^.*\././' | tr 'A-Z' 'a-z' | sort -u | jq -R . | jq -s .)
    else
        local name="${target##*/}"
        [[ "$name" == *.* ]] || return 0
        exts_json=$(printf '.%s\n' "${name##*.}" | tr 'A-Z' 'a-z' | jq -R . | jq -s .)
    fi
    jq -r --argjson exts "$exts_json" '
        .systems | to_entries
        | map(.value as $s | {f: $s.archive_folder, n: ([$exts[] | select(. as $e | $s.accepted_extensions | index($e))] | length)})
        | map(select(.n > 0)) | sort_by(-.n) | .[].f' "$SCHEMA_FILE" 2>/dev/null
}

# Popola RSYNC_FILTERS (case-insensitive) con le sole estensioni date; vuoto = nessun filtro.
build_rsync_filters() {
    RSYNC_FILTERS=()
    local ext body glob c i
    for ext in $1; do
        body="${ext#.}"
        glob="*."
        for ((i = 0; i < ${#body}; i++)); do
            c="${body:i:1}"
            if [[ "$c" =~ [a-zA-Z] ]]; then glob+="[${c,,}${c^^}]"; else glob+="$c"; fi
        done
        RSYNC_FILTERS+=(--include="$glob")
    done
    if [ ${#RSYNC_FILTERS[@]} -gt 0 ]; then
        RSYNC_FILTERS=(-m --include='*/' "${RSYNC_FILTERS[@]}" --exclude='*')
    fi
}

INGEST_MODULE() {
    clear
    echo -e "${HEX_CYAN}=================================================================="
    echo -e "         📥  SMART INGEST ENGINE — SMISTAMENTO MASSIFO"
    echo -e "==================================================================${HEX_RESET}\n"

    # 1. Selezione della cartella sorgente
    read -e -p "Inserisci il percorso della cartella o unità da scansionare: " source_dir
    eval source_dir="$source_dir"

    if [ ! -d "$source_dir" ]; then
        echo -e "\n${HEX_RED}[X] Errore: la cartella sorgente non esiste o non è valida!${HEX_RESET}"
        read -p "Premi [Invio] per tornare al menu..."
        return
    fi

    # 2. Selta della Modalità (Esecuzione Reale vs Simulazione Dry-Run)
    echo -e "\n${HEX_BLUE}Scegli la modalità di esecuzione:${HEX_RESET}"
    echo -e "  ${HEX_GREEN}1)${HEX_RESET} Esecuzione Standard (Copia o Sposta i file realmente)"
    echo -e "  ${HEX_CYAN}2)${HEX_RESET} 🔍 Modalità Dry-Run (Solo simulazione, nessun file viene toccato)"
    read -p "Seleziona [1-2, default: 1]: " run_mode
    run_mode=${run_mode:-1}

    local is_dry_run=false
    if [ "$run_mode" = "2" ]; then
        is_dry_run=true
        echo -e "\n${HEX_YELLOW}[i] ATTIVATA MODALITÀ SIMULAZIONE (DRY-RUN). Nessuna modifica sarà effettuata.${HEX_RESET}\n"
    fi

    # Se non siamo in dry-run, chiediamo se Copiare o Spostare
    local op_mode="1"
    local action_type="--remove-source-files"
    local action_label="Spostamento"

    if [ "$is_dry_run" = false ]; then
        echo -e "${HEX_BLUE}Scegli la modalità di trasferimento:${HEX_RESET}"
        echo -e "  ${HEX_GREEN}1)${HEX_RESET} Sposta (Move) - Trasferisce i file e libera spazio sulla sorgente"
        echo -e "  ${HEX_GREEN}2)${HEX_RESET} Copia (Copy) - Duplica i file lasciando gli originali intatti"
        read -p "Seleziona [1-2, default: 1]: " op_mode
        op_mode=${op_mode:-1}

        if [ "$op_mode" = "2" ]; then
            action_type=""
            action_label="Copia"
        fi
    else
        action_label="Simulazione (Dry-Run)"
    fi

    # Carichiamo il file di mapping JSON attivo
    local json_file="$SCRIPT_DIR/${SYSTEM_TARGET_NAME}2archive.json"
    if [ ! -f "$json_file" ]; then
        echo -e "${HEX_RED}[X] File di mapping JSON non trovato! Esegui prima il bootstrap.${HEX_RESET}"
        read -p "Premi [Invio] per tornare al menu..."
        return
    fi

    echo -e "\n${HEX_CYAN}[🔍] Scansione e analisi della sorgente in corso...${HEX_RESET}\n"

    declare -a plan_sources=()
    declare -a plan_dests=()
    declare -a plan_types=()
    declare -a plan_exts=()
    local unmatched_items=()
    local all_exts ignored_count=0
    all_exts=$(schema_all_exts)

    # Scansione del primo livello della sorgente
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        local full_path="$source_dir/$entry"
        
        local mapped_console
        mapped_console=$(jq -r --arg key "$entry" '.[$key] // empty' "$json_file")

        if [ -n "$mapped_console" ] && [ -d "$full_path" ]; then
            local target_dest="$PATH_ARCHIVIO/$mapped_console"
            plan_sources+=("$full_path")
            plan_dests+=("$target_dest")
            plan_types+=("content")
            plan_exts+=("$(schema_exts_for "$mapped_console" | tr '\n' ' ')")
            echo -e "  ${HEX_GREEN}[✔ Riconosciuto]${HEX_RESET} '$entry' ➔ Destinazione: Archivio/$mapped_console/"
        elif [ -f "$full_path" ] && [ -n "$all_exts" ] && ! ext_in_list "$entry" "$all_exts"; then
            ignored_count=$((ignored_count + 1))
        else
            unmatched_items+=("$entry")
        fi
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -printf '%P\n' | sort)

    if [ "$ignored_count" -gt 0 ]; then
        echo -e "\n${HEX_YELLOW}[i] Ignorati $ignored_count file con estensione non prevista dallo schema.${HEX_RESET}"
    fi

    # 3. Gestione degli elementi non riconosciuti tramite fzf
    if [ ${#unmatched_items[@]} -gt 0 ]; then
        echo -e "\n${HEX_YELLOW}[!] Trovati ${#unmatched_items[@]} elementi non riconosciuti o sciolti.${HEX_RESET}"
        echo -e "    Procediamo alla classificazione interattiva:\n"

        for u_item in "${unmatched_items[@]}"; do
            local full_u_path="$source_dir/$u_item"
            echo -e "  Elemento da classificare: ${HEX_PURPLE}$u_item${HEX_RESET}"

            local suggestions u_default=3
            suggestions=$(suggest_consoles "$full_u_path")
            if [ -n "$suggestions" ]; then
                echo -e "  ${HEX_CYAN}Suggerimento per estensione:${HEX_RESET} $(echo "$suggestions" | paste -sd ',' - | sed 's/,/, /g')"
                u_default=1
            fi

            echo -e "  Scegli l'azione:"
            echo -e "    ${HEX_GREEN}1)${HEX_RESET} Assegna a una console (Usa fzf)"
            echo -e "    ${HEX_YELLOW}2)${HEX_RESET} Parcheggia in _UNSORTED (nell'archivio)"
            echo -e "    ${HEX_RED}3)${HEX_RESET} Salta / Ignora questo elemento"
            read -p "  Scelta [1-3, default: $u_default]: " u_action
            u_action=${u_action:-$u_default}

            case "$u_action" in
                1)
                    local chosen_console
                    # I suggeriti vengono messi in cima alla lista
                    chosen_console=$({ [ -n "$suggestions" ] && echo "$suggestions"; jq -r '.[]' "$json_file" | sort; } | awk 'NF && !seen[$0]++' | fzf --height=10 --prompt="Seleziona console per '$u_item': " || true)
                    
                    if [ -n "$chosen_console" ]; then
                        local target_dest="$PATH_ARCHIVIO/$chosen_console"
                        plan_sources+=("$full_u_path")
                        plan_dests+=("$target_dest")
                        plan_types+=("item")
                        if [ -d "$full_u_path" ]; then
                            plan_exts+=("$(schema_exts_for "$chosen_console" | tr '\n' ' ')")
                        else
                            plan_exts+=("")
                        fi
                        echo -e "  ${HEX_GREEN}➔ Assegnato a: $target_dest${HEX_RESET}\n"
                    else
                        echo -e "  ${HEX_YELLOW}➔ Saltato.${HEX_RESET}\n"
                    fi
                    ;;
                2)
                    local target_dest="$PATH_ARCHIVIO/_UNSORTED"
                    plan_sources+=("$full_u_path")
                    plan_dests+=("$target_dest")
                    plan_types+=("item")
                    plan_exts+=("")
                    echo -e "  ${HEX_YELLOW}➔ Inviato a _UNSORTED${HEX_RESET}\n"
                    ;;
                *)
                    echo -e "  ${HEX_RED}➔ Elemento ignorato.${HEX_RESET}\n"
                    ;;
            esac
        done
    fi

    if [ ${#plan_sources[@]} -eq 0 ]; then
        echo -e "\n${HEX_YELLOW}[i] Nessuna azione pianificata. Operazione interrotta.${HEX_RESET}"
        read -p "Premi [Invio] per tornare al menu..."
        return
    fi

    # 4. Conferma finale prima dell'azione
    echo -e "\n${HEX_PURPLE}------------------------------------------------------------------${HEX_RESET}"
    echo -e "  Totale elementi pianificati: ${HEX_GREEN}${#plan_sources[@]}${HEX_RESET}"
    echo -e "  Modalità: ${HEX_CYAN}$action_label${HEX_RESET}"
    echo -e "${HEX_PURPLE}------------------------------------------------------------------${HEX_RESET}"
    
    if [ "$is_dry_run" = false ]; then
        read -p "Vuoi procedere con l'esecuzione reale? [s/N]: " confirm
        if [[ ! "$confirm" =~ ^[sS][iI]?$ ]]; then
            echo -e "\n${HEX_YELLOW}[i] Operazione annullata dall'utente.${HEX_RESET}"
            read -p "Premi [Invio] per tornare al menu..."
            return
        fi
    else
        echo -e "\n${HEX_CYAN}🔍 Esecuzione simulata in corso (Dry-Run)...${HEX_RESET}\n"
    fi

    # 5. Esecuzione effettiva o simulata
    for i in "${!plan_sources[@]}"; do
        local src="${plan_sources[$i]}"
        local dst="${plan_dests[$i]}"
        local ptype="${plan_types[$i]}"
        local pexts="${plan_exts[$i]}"
        local item_name=$(basename "$src")
        
        echo -e "------------------------------------------------------------------"
        if [ "$is_dry_run" = true ]; then
            echo -e "🧪 [SIMULAZIONE] Sposterei: ${HEX_PURPLE}$item_name${HEX_RESET}"
            echo -e "   📂 Verso la destinazione: $dst"
            echo -e "   ⚙️  Tipo elemento: $ptype"
            [ -n "$pexts" ] && echo -e "   🎯 Solo estensioni: $pexts (+ sottocartelle)"
        else
            mkdir -p "$dst"
            echo -e "➡️ Elaborazione: ${HEX_PURPLE}$item_name${HEX_RESET}"
            echo -e "   📂 Verso: $dst"
            
            build_rsync_filters "$pexts"
            if [ "$ptype" = "content" ]; then
                rsync -av --progress --ignore-existing "${RSYNC_FILTERS[@]}" $action_type "$src/" "$dst/"
            else
                rsync -av --progress "${RSYNC_FILTERS[@]}" $action_type "$src" "$dst/"
            fi
            echo -e "${HEX_GREEN}✔️ Completato.${HEX_RESET}"
        fi
    done

    # Pulizia cartelle vuote solo se è reale ed era uno spostamento
    if [ "$is_dry_run" = false ] && [ "$op_mode" = "1" ]; then
        find "$source_dir" -type d -empty -delete 2>/dev/null
        echo -e "\n${HEX_CYAN}[i] Pulizia cartelle vuote nella sorgente completata.${HEX_RESET}"
    fi

    echo -e "\n${HEX_GREEN}🎉 SMART INGEST TERMINATO CON SUCCESSO!${HEX_RESET}"
    read -p "Premi [Invio] per tornare al menu..."
}

# Avvia la funzione principale del modulo
INGEST_MODULE