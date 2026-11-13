#!/bin/bash

# ==============================================================================
# RETRO-ARCHIVE MANAGER — MAIN TUI DASHBOARD
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/ambiente.env"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap.sh"
INGEST_MODULE="$SCRIPT_DIR/ingest.sh"
# Palette Colori Cyberpunk
HEX_CYAN="\033[1;36m"
HEX_PURPLE="\033[1;35m"
HEX_GREEN="\033[1;32m"
HEX_RED="\033[1;31m"
HEX_YELLOW="\033[1;33m"
HEX_BLUE="\033[1;34m"
HEX_RESET="\033[0m"


# ------------------------------------------------------------------------------
# 1. CONTROLLO E CARICAMENTO AMBIENTE (BOOTSTRAP HOOK)
# ------------------------------------------------------------------------------
verify_environment() {
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${HEX_YELLOW}[!] Nessun ambiente configurato rilevato.${HEX_RESET}"
        if [ -f "$BOOTSTRAP_SCRIPT" ]; then
            echo -e "${HEX_CYAN}[i] Avvio procedura di Bootstrap iniziale...${HEX_RESET}\n"
            bash "$BOOTSTRAP_SCRIPT"
        else
            echo -e "${HEX_RED}[X] Errore critico: script 'bootstrap.sh' non trovato!${HEX_RESET}"
            exit 1
        fi
    fi
    
    # Carica le variabili globali
    source "$ENV_FILE"
}

# ------------------------------------------------------------------------------
# 2. BANNER & DASHBOARD PRINCIPALE (TUI)
# ------------------------------------------------------------------------------
show_banner() {
    clear
    echo -e "${HEX_CYAN}"
    echo "  ██████╗ ███████╗████████╗██████╗       ███╗   ███╗ █████╗ ███╗   ██╗"
    echo "  ██╔══██╗██╔════5╚══██╔══╝██╔══██╗      ████╗ ████║██╔══██╗████╗  ██║"
    echo "  ██████╔5█████╗     ██║   ██████╔╝      ██╔████╔██║███████║██╔██╗ ██║"
    echo "  ██╔══██╗██╔══╝     ██║   ██╔══██╗      ██║╚██╔╝██║██╔══██║██║╚██╗██║"
    echo "  ██║  ██║███████╗   ██║   ██║  ██║      ██║ ╚═╝ ██║██║  ██║██║ ╚████║"
    echo "  ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝      ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝"
    echo -e "${HEX_RESET}"
    echo -e "${HEX_PURPLE}  ================================================================"
    echo -e "   ARCHIVIO: ${HEX_GREEN}$PATH_ARCHIVIO${HEX_RESET}"
    echo -e "   TARGET:   ${HEX_GREEN}$PATH_SHARE_ROOT ($SYSTEM_TARGET_NAME)${HEX_RESET}"
    echo -e "${HEX_PURPLE}  ================================================================${HEX_RESET}\n"
}

# ------------------------------------------------------------------------------
# 3. MOCK FUNCTIONS (I TRE PILASTRI DEL CORE)
# ------------------------------------------------------------------------------
run_smart_ingest() {
    # Verifica che il file esista prima di chiamarlo
    if [ -f "$INGEST_MODULE" ]; then
        # Esegue il modulo (puoi caricarlo con source o eseguirlo in subshell)
        bash "$INGEST_MODULE"
    else
        echo -e "${HEX_RED}[X] Errore: Modulo ingest.sh non trovato!${HEX_RESET}"
        read -p "Premi [Invio] per tornare al menu..."
    fi
}

run_deploy_system() {
    echo -e "\n${HEX_YELLOW}[🚧] Modulo 'Deploy a Sistema' in fase di sviluppo...${HEX_RESET}"
    echo -e "Qui useremo fzf per cercare e inviare i giochi dall'archivio a Batocera."
    read -p "Premi [Invio] per tornare al menu..."
}

run_vault_backup() {
    echo -e "\n${HEX_YELLOW}[🚧] Modulo 'Vault & Backup' in fase di sviluppo...${HEX_RESET}"
    echo -e "Qui gestiremo il backup della partizione SHARE e la compressione dell'archivio."
    read -p "Premi [Invio] per tornare al menu..."
}

reconfigure_env() {
    echo -e "\n${HEX_CYAN}[i] Forzatura riconfigurazione ambiente...${HEX_RESET}"
    rm -f "$ENV_FILE"
    verify_environment
}

# ------------------------------------------------------------------------------
# 4. LOOP PRINCIPALE DEL MENU
# ------------------------------------------------------------------------------
main_menu() {
    verify_environment

    while true; do
        show_banner
        echo -e "  ${HEX_BLUE}Scegli un'operazione:${HEX_RESET}\n"
        echo -e "    ${HEX_GREEN}1)${HEX_RESET} 📥 Smart Ingest (Smista e pulisci da sorgente esterna all'Archivio)"
        echo -e "    ${HEX_GREEN}2)${HEX_RESET} 📤 Deploy a Sistema (Invia giochi dall'Archivio a Batocera)"
        echo -e "    ${HEX_GREEN}3)${HEX_RESET} 📦 Vault & Backup (Backup partizione SHARE / Export Archivio)"
        echo -e "    ${HEX_YELLOW}4)${HEX_RESET} ⚙️  Riconfigura / Reset Ambiente"
        echo -e "    ${HEX_RED}5)${HEX_RESET} ❌ Esci\n"
        
        read -p "  Inserisci la tua scelta [1-5]: " choice
        
        case "$choice" in
            1) run_smart_ingest ;;
            2) run_deploy_system ;;
            3) run_vault_backup ;;
            4) reconfigure_env ;;
            5) 
                echo -e "\n${HEX_CYAN}Uscita da Retro-Archive Manager. Ciao mama! 👋${HEX_RESET}\n"
                exit 0 
                ;;
            *) 
                echo -e "\n${HEX_RED}[X] Scelta non valida!${HEX_RESET}"
                sleep 1
                ;;
        esac
    done
}

# Avvio applicazione
main_menu