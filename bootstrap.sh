#!/bin/bash

# ==============================================================================
# RETRO-ARCHIVE MANAGER — FASE 1: BOOTSTRAP UNIVERSE & SHARE DETECTOR
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/ambiente.env"
JSON_MAPPING_FILE="$SCRIPT_DIR/system2archive.json"

# Palette Colori Cyberpunk
HEX_CYAN="\033[1;36m"
HEX_PURPLE="\033[1;35m"
HEX_GREEN="\033[1;32m"
HEX_RED="\033[1;31m"
HEX_YELLOW="\033[1;33m"
HEX_RESET="\033[0m"

# ------------------------------------------------------------------------------
# 1. VERIFICA DIPENDENZE (SOLO CONTROLLO - NO DOWNLOAD AUTOMATICI)
# ------------------------------------------------------------------------------
check_dependencies() {
    local deps=("fzf" "jq" "rsync")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${HEX_RED}[!] MANCANO DELLE DIPENDENZE PER IL CORRETTO FUNZIONAMENTO:${HEX_RESET}"
        echo -e "    Comandi mancanti: ${HEX_YELLOW}${missing[*]}${HEX_RESET}\n"
        echo -e "    Installale manualmente (es. sudo apt install ${missing[*]}) prima di continuare."
    fi
}

# ------------------------------------------------------------------------------
# 2. RILEVAMENTO DINAMICO STRUTTURA SHARE / USERDATA
# ------------------------------------------------------------------------------
find_system_paths() {
    local root_path="$1"
    
    # Inizializziamo le variabili vuote
    TARGET_ROMS=""
    TARGET_SAVES=""
    TARGET_BIOS=""

    # 1. Ricerca intelligente e dinamica della cartella ROMS ovunque si trovi dentro root_path
    # (questo risolve brillantemente strutture come /media/mama/SHARE/batocera/roms)
    if [ -d "$root_path/roms" ]; then
        TARGET_ROMS="$root_path/roms"
    else
        # Cerca la prima cartella 'roms' figliastra all'interno del percorso dato
        local found_roms
        found_roms=$(find "$root_path" -type d -name "roms" -print -quit 2>/dev/null)
        if [ -n "$found_roms" ]; then
            TARGET_ROMS="$found_roms"
        fi
    fi

    # 2. Se abbiamo trovato la cartella ROMS, ricaviamo la "base" del sistema 
    # (es. se TARGET_ROMS è /media/mama/SHARE/batocera/roms, la base è /media/mama/SHARE/batocera)
    if [ -n "$TARGET_ROMS" ]; then
        local sys_base
        sys_base="$(dirname "$TARGET_ROMS")"
        
        # Cerchiamo saves e bios in relazione alla stessa base o dentro root_path
        [ -d "$sys_base/saves" ] && TARGET_SAVES="$sys_base/saves"
        [ -d "$sys_base/bios" ]  && TARGET_BIOS="$sys_base/bios"
    fi

    # Fallback di sicurezza se saves/bios non sono vicini a roms ma stanno nella root
    [ -z "$TARGET_SAVES" ] && [ -d "$root_path/saves" ] && TARGET_SAVES="$root_path/saves"
    [ -z "$TARGET_BIOS" ]  && [ -d "$root_path/bios" ]  && TARGET_BIOS="$root_path/bios"
}

# ------------------------------------------------------------------------------
# 3. CONFIGURAZIONE AMBIENTE (ambiente.env)
# ------------------------------------------------------------------------------
init_environment() {
    echo -e "${HEX_CYAN}"
    echo "=================================================================="
    echo "     🕹️  RETRO-ARCHIVE MANAGER — INITIAL BOOTSTRAP SETUP  🕹️"
    echo "=================================================================="
    echo -e "${HEX_RESET}"

    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        echo -e "${HEX_GREEN}[✔] Configurazione caricata da ambiente.env${HEX_RESET}"
        echo -e "   • Percorso Archivio: ${HEX_PURPLE}$PATH_ARCHIVIO${HEX_RESET}"
        echo -e "   • Radice SHARE:     ${HEX_PURPLE}$PATH_SHARE_ROOT${HEX_RESET}"
        echo -e "   • Cartella ROMS:     ${HEX_PURPLE}$PATH_ROMS${HEX_RESET}"
        echo -e "   • Target OS:         ${HEX_PURPLE}$SYSTEM_TARGET_NAME${HEX_RESET}"
    else
        echo -e "${HEX_YELLOW}[!] Nessuna configurazione trovata. Configurazione guidata:${HEX_RESET}\n"

        # 1. Prompt ARCHIVIO
        read -e -p "1. Inserisci il percorso dell'ARCHIVIO (es. /media/mama/Retro-Stuff): " input_archive
        eval input_archive="$input_archive"
        while [ ! -d "$input_archive" ]; do
            echo -e "${HEX_RED}[X] Percorso archivio non valido! Riprova.${HEX_RESET}"
            read -e -p "   Percorso ARCHIVIO: " input_archive
            eval input_archive="$input_archive"
        done

        # 2. Prompt SHARE ROOT (Batocera, Recalbox, RetroBat, ecc.)
        read -e -p "2. Inserisci la radice della partizione SHARE/USERDATA (es. /media/mama/SHARE): " input_share
        eval input_share="$input_share"
        
        find_system_paths "$input_share"

        while [ -z "$TARGET_ROMS" ]; do
            echo -e "${HEX_RED}[X] Impossibile trovare la cartella 'roms' all'interno di $input_share!${HEX_RESET}"
            read -e -p "   Reinserisci la radice SHARE/USERDATA: " input_share
            eval input_share="$input_share"
            find_system_paths "$input_share"
        done

        # Detect nome sistema
        read -e -p "3. Identificativo del sistema target [default: batocera]: " input_target_name
        input_target_name=${input_target_name:-batocera}

        # Salvataggio nel file ambiente.env
        cat <<EOF > "$ENV_FILE"
# CONFIGURAZIONE AMBIENTE RETRO-ARCHIVE MANAGER
PATH_ARCHIVIO="$input_archive"
PATH_SHARE_ROOT="$input_share"
PATH_ROMS="$TARGET_ROMS"
PATH_SAVES="$TARGET_SAVES"
PATH_BIOS="$TARGET_BIOS"
SYSTEM_TARGET_NAME="$input_target_name"
ALLINEAMENTO_COMPLETATO=false
EOF

        source "$ENV_FILE"
        echo -e "\n${HEX_GREEN}[✔] File ambiente.env creato con successo!${HEX_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# 4. MAPPING DINAMICO SISTEMI (system2archive.json)
# ------------------------------------------------------------------------------
init_mapping() {
    if [ ! -d "$PATH_ROMS" ]; then
        echo -e "${HEX_RED}[X] Errore: la cartella ROMS '$PATH_ROMS' non esiste.${HEX_RESET}"
        return 1
    fi

    echo -e "\n${HEX_CYAN}[🔍] Scansione dei sistemi presenti in SHARE ($SYSTEM_TARGET_NAME)...${HEX_RESET}"

    # Usa un file generico di mapping basato sul nome del sistema scelto
    JSON_MAPPING_FILE="$SCRIPT_DIR/${SYSTEM_TARGET_NAME}2archive.json"

    if [ ! -f "$JSON_MAPPING_FILE" ]; then
        echo "{}" > "$JSON_MAPPING_FILE"
        
        # Scansiona tutte le directory dentro roms/
        find "$PATH_ROMS" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | while read -r console; do
            jq --arg key "$console" --arg val "$console" '. + {($key): $val}' "$JSON_MAPPING_FILE" > "$JSON_MAPPING_FILE.tmp" && mv "$JSON_MAPPING_FILE.tmp" "$JSON_MAPPING_FILE"
        done
        echo -e "${HEX_GREEN}[✔] Generato file di mapping: '$(basename "$JSON_MAPPING_FILE")'${HEX_RESET}"
    else
        echo -e "${HEX_GREEN}[✔] File di mapping '$(basename "$JSON_MAPPING_FILE")' caricato.${HEX_RESET}"
    fi

    # Mappatura salvataggi/bios rilevati
    [ -n "$PATH_SAVES" ] && echo -e "   • Cartella Saves rilevata: ${HEX_PURPLE}$PATH_SAVES${HEX_RESET}"
    [ -n "$PATH_BIOS" ]  && echo -e "   • Cartella Bios rilevata:  ${HEX_PURPLE}$PATH_BIOS${HEX_RESET}"
}

# ------------------------------------------------------------------------------
# ESECUZIONE
# ------------------------------------------------------------------------------
check_dependencies
init_environment
init_mapping

echo -e "\n${HEX_PURPLE}------------------------------------------------------------------${HEX_RESET}"
echo -e "${HEX_GREEN}🚀 BOOTSTRAP FASE 1 COMPLETATO CON SUCCESSO!${HEX_RESET}"
echo -e "${HEX_PURPLE}------------------------------------------------------------------${HEX_RESET}"