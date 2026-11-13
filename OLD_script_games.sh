#!/bin/bash

# 1. Verifica che zenity sia installato
if ! command -v zenity &> /dev/null; then
    sudo apt update && sudo apt install zenity -y
fi

# 2. Percorsi di default e configurabili
CONFIG_FILE="$HOME/.config/game_manager_path.conf"
DEFAULT_ARCHIVE="/media/mama/Retro-Stuff"
DEFAULT_SOURCE="$HOME/Scaricati"

# Funzione di normalizzazione con Regex per i nomi delle ROM
clean_rom_name() {
    local name="$1"
    name=$(echo "$name" | sed -E 's/\.[^./]+$//')
    name=$(echo "$name" | sed -E 's/[([].*$//')
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | xargs)
    echo "$name"
}

# Controllo Batocera Home
if [ -f "$CONFIG_FILE" ]; then
    BATOCERA_HOME=$(cat "$CONFIG_FILE")
fi

if [ -z "$BATOCERA_HOME" ] || [ ! -d "$BATOCERA_HOME" ]; then
    BATOCERA_HOME=$(zenity --file-selection --directory --title="Seleziona la cartella Home di Batocera" --filename="/media/mama/")
    [ -z "$BATOCERA_HOME" ] && exit 0
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$BATOCERA_HOME" > "$CONFIG_FILE"
fi

ROMS_PATH="$BATOCERA_HOME/roms"

if [ ! -d "$ROMS_PATH" ]; then
    zenity --error --title="Errore" --text="La cartella roms non esiste nel percorso specificato:\n$ROMS_PATH"
    rm -f "$CONFIG_FILE"
    exit 1
fi

# Lettura dinamica delle console da Batocera / Archivio
console_list=$(find "$ROMS_PATH" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

if [ -z "$console_list" ]; then
    zenity --error --title="Errore" --text="Nessuna cartella di console trovata dentro:\n$ROMS_PATH"
    exit 1
fi

# 3. Menu principale pulito (senza pango per evitare crash di sintassi)
scelta=$(zenity --list --title="Game Backup & Deploy Manager" \
    --text="Archivio di riferimento attuale:\n[$DEFAULT_ARCHIVE]\n\nScegli un'operazione:" \
    --column="Opzione" --column="Descrizione" \
    "1" "📥 Importa Singolo (Sposta un elemento con controllo Regex)" \
    "2" "📦 Scansiona Dir e Archivia in Massa (Smart Batch con Anteprima)" \
    "3" "📤 Invia a Batocera (Copia dall'Archivio alla Console)" \
    --width=650 --height=260)

case $scelta in
    "1")
        # --- MODALITA' IMPORTAZIONE SINGOLA ---
        source_dir=$(zenity --file-selection --directory --title="Seleziona la cartella sorgente" --filename="$DEFAULT_SOURCE/")
        [ -z "$source_dir" ] && exit 0

        source_items=$(find "$source_dir" -mindepth 1 -maxdepth 1 -printf '%P\n' | sort)
        [ -z "$source_items" ] && { zenity --error --text="La cartella è vuota."; exit 1; }

        zenity_args=("--list" "--title=Seleziona elemento da importare" "--column=Elementi Disponibili")
        while IFS= read -r item; do zenity_args+=("$item"); done <<< "$source_items"

        selected_item=$(zenity "${zenity_args[@]}" --width=500 --height=500)
        [ -z "$selected_item" ] && exit 0
        full_source_path="$source_dir/$selected_item"

        zenity_args_console=("--list" "--title=Seleziona Piattaforma di destinazione" "--column=Console")
        while IFS= read -r console; do zenity_args_console+=("$console"); done <<< "$console_list"

        selected_console=$(zenity "${zenity_args_console[@]}" --width=400 --height=500)
        [ -z "$selected_console" ] && exit 0

        target_archive="$DEFAULT_ARCHIVE/$selected_console"
        mkdir -p "$target_archive"

        clean_input=$(clean_rom_name "$selected_item")
        duplicate_found=""
        if [ -d "$target_archive" ]; then
            while IFS= read -r existing_item; do
                [ -z "$existing_item" ] && continue
                [ "$clean_input" = "$(clean_rom_name "$existing_item")" ] && { duplicate_found="$existing_item"; break; }
            done < <(find "$target_archive" -mindepth 1 -maxdepth 1 -printf '%P\n')
        fi

        if [ -n "$duplicate_found" ]; then
            zenity --question --title="⚠️ Possibile Doppione!" \
                --text="Il gioco '$selected_item' sembra già esistere nell'archivio:\n[$target_archive]\n\nCome:\n• $duplicate_found\n\nVuoi procedere comunque?" --width=550
            [ $? -ne 0 ] && exit 0
        fi

        zenity --question --title="Conferma Spostamento" \
            --text="Stai per SPOSTARE:\n'$selected_item'\n\nVerso l'Archivio:\n[$target_archive]\n\nVuoi procedere?" --width=550
        [ $? -ne 0 ] && exit 0

        echo "⏳ Spostamento di '$selected_item' in corso verso $target_archive..."
        rsync -av --progress --remove-source-files "$full_source_path" "$target_archive/"
        
        [ -d "$full_source_path" ] && rm -rf "$full_source_path"
        find "$source_dir" -type d -empty -delete 2>/dev/null

        zenity --info --title="Completato" --text="✅ Spostamento completato!\nFile originale rimosso con successo dalla sorgente."
        ;;

    "2")
        # --- MODALITA' SMART BATCH CON ANTEPRIMA ---
        batch_dir=$(zenity --file-selection --directory --title="Seleziona la cartella disorganizzata da scansionare in massa" --filename="$DEFAULT_SOURCE/")
        [ -z "$batch_dir" ] && exit 0

        plan_sources=()
        plan_dests=()
        plan_types=()
        
        preview_text="=========================================\n"
        preview_text+="  RIEPILOGO SPOSTAMENTI VERSO ARCHIVIO\n"
        preview_text+="  Path: $DEFAULT_ARCHIVE\n"
        preview_text+="=========================================\n\n"

        unmatched_items=()

        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            full_path="$batch_dir/$entry"
            
            found_console=""
            if [ -d "$full_path" ]; then
                while IFS= read -r c; do
                    if [ "${entry,,}" = "${c,,}" ]; then
                        found_console="$c"
                        break
                    fi
                done <<< "$console_list"
            fi

            if [ -n "$found_console" ]; then
                target_dest="$DEFAULT_ARCHIVE/$found_console"
                plan_sources+=("$full_path")
                plan_dests+=("$target_dest")
                plan_types+=("content")
                preview_text+="[CONSOLE RICONOSCIUTA: $found_console]\n"
                preview_text+="📁 Sorgente: '$entry'\n"
                preview_text+="➔ Destinazione: $target_dest/\n\n"
            else
                unmatched_items+=("$entry")
            fi
        done < <(find "$batch_dir" -mindepth 1 -maxdepth 1 -printf '%P\n')

        # Gestione unmatched
        if [ ${#unmatched_items[@]} -gt 0 ]; then
            for u_item in "${unmatched_items[@]}"; do
                full_u_path="$batch_dir/$u_item"
                
                action=$(zenity --list --title="Elemento Non Riconosciuto Trovato" \
                    --text="L'elemento '$u_item' non corrisponde a nessuna console nota.\nScegli come gestirlo:" \
                    --column="Azione" \
                    "1. Assegna a una console esistente" \
                    "2. Sposta in _UNSORTED (parcheggio temporaneo)" \
                    "3. Salta / Ignora questo elemento" \
                    --width=600 --height=260)

                case "$action" in
                    "1. Assegna a una console esistente")
                        zenity_args_console=("--list" "--title=Assegna: $u_item" "--column=Console")
                        while IFS= read -r console; do zenity_args_console+=("$console"); done <<< "$console_list"
                        
                        chosen_c=$(zenity "${zenity_args_console[@]}" --width=400 --height=400)
                        if [ -n "$chosen_c" ]; then
                            target_dest="$DEFAULT_ARCHIVE/$chosen_c"
                            plan_sources+=("$full_u_path")
                            plan_dests+=("$target_dest")
                            plan_types+=("item")
                            preview_text+="[ASSEGNATO A: $chosen_c]\n"
                            preview_text+="📦 Elemento: '$u_item'\n"
                            preview_text+="➔ Destinazione: $target_dest/\n\n"
                        fi
                        ;;
                    "2. Sposta in _UNSORTED (parcheggio temporaneo)")
                        target_dest="$DEFAULT_ARCHIVE/_UNSORTED"
                        plan_sources+=("$full_u_path")
                        plan_dests+=("$target_dest")
                        plan_types+=("item")
                        preview_text+="[INVIATO A _UNSORTED]\n"
                        preview_text+="📦 Elemento: '$u_item'\n"
                        preview_text+="➔ Destinazione: $target_dest/\n\n"
                        ;;
                    *)
                        preview_text+="[SALTATO]\n"
                        preview_text+="❌ Elemento: '$u_item'\n\n"
                        ;;
                esac
            done
        fi

        if [ ${#plan_sources[@]} -eq 0 ]; then
            zenity --info --title="Nessuna azione" --text="Nessun elemento valido da spostare."
            exit 0
        fi

        temp_preview=$(mktemp)
        echo -e "$preview_text" > "$temp_preview"

        zenity --text-info --title="🔍 Anteprima Operazioni (Archivio: $DEFAULT_ARCHIVE)" \
            --filename="$temp_preview" --width=750 --height=550 \
            --checkbox="CONFERMO: Voglio eseguire tutti gli spostamenti sopra elencati"

        if [ $? -ne 0 ]; then
            rm -f "$temp_preview"
            zenity --info --title="Annullato" --text="Operazione annullata. Nessun file è stato toccato."
            exit 0
        fi
        rm -f "$temp_preview"

        echo "🚀 Avvio spostamenti in massa verso l'archivio: $DEFAULT_ARCHIVE"
        
        for i in "${!plan_sources[@]}"; do
            src="${plan_sources[$i]}"
            dst="${plan_dests[$i]}"
            ptype="${plan_types[$i]}"
            
            mkdir -p "$dst"
            item_name=$(basename "$src")
            
            echo "---------------------------------------------------"
            echo "➡️ Spostamento in corso: '$item_name'"
            echo "   📂 Verso: $dst"
            
            if [ "$ptype" = "content" ]; then
                rsync -av --progress --ignore-existing --remove-source-files "$src/" "$dst/"
            else
                rsync -av --progress --remove-source-files "$src" "$dst/"
            fi
            
            echo "✔️ Completato e file originale rimosso con successo."
        done

        find "$batch_dir" -type d -empty -delete 2>/dev/null

        zenity --info --title="Batch Completato" \
            --text="✅ Smistamento massivo completato con successo!"
        ;;

    "3")
        # --- MODALITA' DISTRIBUZIONE A CONSOLE ---
        zenity_args=("--list" "--title=Seleziona Console Batocera" "--column=Console")
        while IFS= read -r console; do zenity_args+=("$console"); done <<< "$console_list"

        selected_console=$(zenity "${zenity_args[@]}" --width=400 --height=500)
        [ -z "$selected_console" ] && exit 0

        target_batocera_console="$ROMS_PATH/$selected_console"
        archive_console_path="$DEFAULT_ARCHIVE/$selected_console"

        gioco=$(zenity --file-selection --title="Preleva dall'Archivio [$archive_console_path]" --filename="$archive_console_path/")
        [ -z "$gioco" ] && exit 0

        zenity --question --title="Conferma Copia su Batocera" \
            --text="Stai prelevando dall'Archivio:\n[$archive_console_path]\n\nPer copiare il gioco:\n'$(basename "$gioco")'\n\nVerso Batocera:\n[$selected_console]\n\nProcedere?" --width=600
        [ $? -ne 0 ] && exit 0

        echo "⏳ Copia di '$(basename "$gioco")' verso Batocera in corso..."
        rsync -av --progress "$gioco" "$target_batocera_console/"
        
        zenity --info --title="Completato" --text="✅ Gioco copiato con successo sulla console Batocera!"
        ;;
esac