#!/bin/bash

# ==============================================================================
# GENERATORE DI FIXTURE PER LO SMART INGEST
# Crea una sandbox con file vuoti (0 byte) e un manifest con l'esito atteso.
# Non tocca ambiente.env, archivio o ROM reali.
# ==============================================================================

set -u

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GM_DIR="$(dirname "$TOOLS_DIR")"
SCHEMA="$GM_DIR/archive_schema.json"
MARKER=".gm-fixture"

die() { echo "Errore: $*" >&2; exit 1; }

usage() {
    cat <<EOF
Uso: $(basename "$0") [--out DIR] [--seed N] [--size small|medium|large]
     $(basename "$0") --clean DIR

  --out DIR     cartella di destinazione (nuova o vuota; default: temporanea)
  --seed N      seme numerico per riprodurre lo stesso scenario
  --size S      quantita' di giochi: small, medium (default), large
  --clean DIR   elimina una sandbox creata da questo script (richiede $MARKER)
EOF
}

OUT="" SEED="" SIZE="medium" CLEAN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --out)   [ $# -ge 2 ] || die "--out richiede un valore"; OUT="$2"; shift 2 ;;
        --seed)  [ $# -ge 2 ] || die "--seed richiede un valore"; SEED="$2"; shift 2 ;;
        --size)  [ $# -ge 2 ] || die "--size richiede un valore"; SIZE="$2"; shift 2 ;;
        --clean) [ $# -ge 2 ] || die "--clean richiede un valore"; CLEAN="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

if [ -n "$CLEAN" ]; then
    [ -f "$CLEAN/$MARKER" ] || die "'$CLEAN' non e' una sandbox di fixture (manca $MARKER)."
    rm -rf -- "$CLEAN"
    echo "Sandbox rimossa: $CLEAN"
    exit 0
fi

case "$SIZE" in
    small) MULT=1 ;;
    medium) MULT=3 ;;
    large) MULT=8 ;;
    *) die "--size deve essere small, medium o large" ;;
esac

[ -f "$SCHEMA" ] || die "schema non trovato: $SCHEMA"

if [ -z "$SEED" ]; then SEED=$(( $(date +%s) % 32768 )); fi
[[ "$SEED" =~ ^[0-9]+$ ]] || die "--seed deve essere un numero"

if [ -z "$OUT" ]; then
    OUT="$(mktemp -d "${TMPDIR:-/tmp}/gm-fixture.XXXXXX")" || die "mktemp fallito"
else
    if [ -e "$OUT" ] && { [ ! -d "$OUT" ] || [ -n "$(ls -A -- "$OUT")" ]; }; then
        die "'$OUT' esiste e non e' una cartella vuota."
    fi
    mkdir -p -- "$OUT" || die "impossibile creare '$OUT'"
fi
OUT="$(cd "$OUT" && pwd)"

# Il percorso finisce in un file .env che viene caricato con source.
case "$OUT" in
    *[\"\$\`\\]*) die "il percorso di output non puo' contenere \" \$ \` o \\" ;;
esac

SRC="$OUT/Download Giochi"
ARC="$OUT/archive"
SHARE="$OUT/share"
SCRIPTS="$OUT/scripts"
MANIFEST="$OUT/manifest.txt"

# ------------------------------------------------------------------------------
# Schema: estensioni accettate per console (lette da archive_schema.json)
# ------------------------------------------------------------------------------
declare -A SCHEMA_EXTS=()
while IFS='|' read -r sys exts; do
    read -ra _tmp <<< "$exts"
    SCHEMA_EXTS[$sys]="${_tmp[*]}"
done < <(awk '
    /"archive_folder"/ { gsub(/.*: *"|".*/, ""); sys = $0 }
    /"accepted_extensions"/ { s = $0; sub(/.*\[/, "", s); sub(/\].*/, "", s); gsub(/[" ,]+/, " ", s); print sys "|" s }
' "$SCHEMA")
[ ${#SCHEMA_EXTS[@]} -gt 0 ] || die "nessuna console letta da $SCHEMA"
mapfile -t SYSTEMS < <(printf '%s\n' "${!SCHEMA_EXTS[@]}" | sort)

# ------------------------------------------------------------------------------
# Generazione casuale (niente $(...) attorno a RANDOM: il seme verrebbe perso)
# ------------------------------------------------------------------------------
RANDOM=$SEED
declare -A SEEN=()
ADJ=(Crystal Shadow Iron Neon Crimson Silent Lunar Turbo Hyper Royal Phantom Golden Frozen Rapid Savage Mystic Atomic Hidden)
NOUN=(Harbor Quest Legends Racer Kingdom Fighters Odyssey Tactics Chronicles Rally Dungeon Striker Voyage Arena Saga Blaster Empire Rangers)
NAME=(Jack Dexter Mira Kojo Rex Luna Toby Nova Axel Zara Ivo Bruno)
REGION=("USA" "Europe" "Japan" "World" "USA, Europe" "Germany" "France" "Italy" "Spain")
GROUP=(RAZOR FAiRLiGHT SKIDROW HOODLUM PARADOX)
JUNK_EXT=(.txt .nfo .exe .jpg .pdf .cue .url .png)

R=0 P="" TITLE="" TAG="" GAME="" EXT="" SUGG="-"

rnd() { R=$((RANDOM % $1)); }
pick() { local -n _arr=$1; rnd ${#_arr[@]}; P="${_arr[$R]}"; }

make_title() {
    local a b tries=0
    while :; do
        rnd 5
        case $R in
            0) pick ADJ; a=$P; pick NOUN; TITLE="$a $P" ;;
            1) pick NAME; a=$P; pick NAME; TITLE="$a & $P" ;;
            2) pick NOUN; a=$P; rnd 4; TITLE="$a $((R + 2))" ;;
            3) pick NOUN; a=$P; pick ADJ; TITLE="The $a of $P" ;;
            4) pick ADJ; a=$P; pick NOUN; b=$P; pick NAME; TITLE="$a $b - $P's Revenge" ;;
        esac
        tries=$((tries + 1))
        [ "$tries" -gt 40 ] && TITLE="$TITLE $tries"
        if [ -z "${SEEN[$TITLE]:-}" ]; then SEEN[$TITLE]=1; break; fi
    done
}

make_tag() {
    pick REGION; TAG=" ($P)"
    rnd 4; [ "$R" -eq 0 ] && TAG+=" (Rev A)"
    rnd 5; [ "$R" -eq 0 ] && TAG+=" (En,Fr,De)"
    rnd 6; [ "$R" -eq 0 ] && TAG+=" [!]"
}

# GAME: nome in stile No-Intro, oppure in stile scene
make_game() {
    make_title; rnd 8
    if [ "$R" -eq 0 ]; then
        pick GROUP
        GAME="${TITLE// /.}"; GAME="${GAME//&/and}-$P"
    else
        make_tag; GAME="$TITLE$TAG"
    fi
}

# EXT: estensione casuale accettata da una console (a volte maiuscola)
pick_ext() {
    local -a e
    read -ra e <<< "${SCHEMA_EXTS[$1]}"
    rnd ${#e[@]}; EXT="${e[$R]}"
    rnd 6; [ "$R" -eq 0 ] && EXT="${EXT^^}"
}

# SUGG: console suggerite per un elenco di estensioni (come fa l'ingest)
suggest_for() {
    local sys e n
    local -a lines=()
    for sys in "${SYSTEMS[@]}"; do
        n=0
        for e in $(printf '%s\n' $1 | tr 'A-Z' 'a-z' | sort -u); do
            [[ " ${SCHEMA_EXTS[$sys]} " == *" $e "* ]] && n=$((n + 1))
        done
        [ "$n" -gt 0 ] && lines+=("$n $sys")
    done
    SUGG="-"
    if [ ${#lines[@]} -gt 0 ]; then
        SUGG="$(printf '%s\n' "${lines[@]}" | sort -k1,1nr -k2,2 | awk '{ printf "%s%s", (NR > 1 ? "," : ""), $2 }')"
    fi
}

ext_of() {
    local name="${1##*/}"
    EXT_L=""
    [[ "$name" == *.* ]] && EXT_L=".${name##*.}"
    EXT_L="${EXT_L,,}"
}

# ------------------------------------------------------------------------------
# Creazione file + manifest (KIND, SOURCE, TARGET, SUGGEST)
# ------------------------------------------------------------------------------
mkf() { mkdir -p -- "${1%/*}"; : > "$1"; }
rec() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$MANIFEST"; }

# File dentro una cartella console riconosciuta: il contenuto finisce in archive/<console>/
recognized_file() {
    local console="$1" rel="$2" kind="${3:-}"
    mkf "$SRC/$rel"
    ext_of "$rel"
    if [ -z "${SCHEMA_EXTS[$console]+x}" ]; then
        rec UNFILTERED "$rel" "$rel" "-"
    elif [[ " ${SCHEMA_EXTS[$console]} " == *" $EXT_L "* ]]; then
        [ -n "$kind" ] || kind=RECOGNIZED
        [ "$kind" = DUPLICATE ] && mkf "$ARC/$rel"
        rec "$kind" "$rel" "$rel" "-"
    else
        rec FILTERED "$rel" "-" "-"
    fi
}

# File sciolto al primo livello della sorgente
loose_file() {
    local rel="$1"
    mkf "$SRC/$rel"
    ext_of "$rel"
    if [ -n "$EXT_L" ] && grep -qxF -- "$EXT_L" <<< "$ALL_EXTS"; then
        suggest_for "$EXT_L"
        rec LOOSE "$rel" "?/$rel" "$SUGG"
    else
        rec LOOSE_IGNORED "$rel" "-" "-"
    fi
}

# Cartella non riconosciuta: i suggerimenti dipendono da tutti i file contenuti
unmatched_folder() {
    local dir="$1" f exts="" kind
    shift
    for f in "$@"; do ext_of "$f"; exts+="$EXT_L "; done
    suggest_for "$exts"
    for f in "$@"; do
        mkf "$SRC/$dir/$f"
        ext_of "$f"
        if [ -n "$EXT_L" ] && grep -qxF -- "$EXT_L" <<< "$ALL_EXTS"; then
            rec FOLDER_GAME "$dir/$f" "?/$dir/$f" "$SUGG"
        else
            rec FOLDER_JUNK "$dir/$f" "-" "$SUGG"
        fi
    done
}

ALL_EXTS="$(for s in "${SYSTEMS[@]}"; do printf '%s\n' ${SCHEMA_EXTS[$s]}; done | sort -u)"

# ------------------------------------------------------------------------------
# Sandbox: roms finte, archivio, copia degli script con ambiente proprio
# ------------------------------------------------------------------------------
ROM_CONSOLES=(gba megadrive psp psx ps2 snes)
mkdir -p -- "$SRC" "$ARC" "$SCRIPTS"
for c in "${ROM_CONSOLES[@]}"; do mkdir -p -- "$SHARE/roms/$c"; done
: > "$OUT/$MARKER"
printf '# KIND\tSOURCE (rel. a "Download Giochi")\tTARGET (rel. a archive; ? = console scelta)\tSUGGEST (insieme; ordine non garantito sui pareggi)\n' > "$MANIFEST"

cp -- "$GM_DIR/gamemanager.sh" "$GM_DIR/ingest.sh" "$SCHEMA" "$SCRIPTS/"
cat > "$SCRIPTS/ambiente.env" <<EOF
PATH_ARCHIVIO="$ARC"
PATH_SHARE_ROOT="$SHARE"
PATH_ROMS="$SHARE/roms"
PATH_SAVES=""
PATH_BIOS=""
SYSTEM_TARGET_NAME="fixture"
ALLINEAMENTO_COMPLETATO=false
EOF
{
    printf '{'
    first=1
    for c in "${ROM_CONSOLES[@]}"; do
        [ "$first" -eq 1 ] || printf ','
        printf '"%s":"%s"' "$c" "$c"
        first=0
    done
    printf '}\n'
} > "$SCRIPTS/fixture2archive.json"

# ------------------------------------------------------------------------------
# Scenario 1: cartelle console riconosciute
# ------------------------------------------------------------------------------
for ((i = 0; i < 4 * MULT; i++)); do
    make_game; pick_ext snes
    kind=""; [ "$i" -lt 2 ] && kind=DUPLICATE
    recognized_file snes "snes/$GAME$EXT" "$kind"
done
for ((i = 0; i < MULT; i++)); do
    make_game; pick_ext snes
    recognized_file snes "snes/$GAME/$GAME$EXT"
    recognized_file snes "snes/$GAME/$GAME.srm"
    recognized_file snes "snes/$GAME/readme.txt"
done
for ((i = 0; i < 2; i++)); do
    make_game; pick_ext snes
    recognized_file snes "snes/Translations & Hacks/$GAME$EXT"
done
recognized_file snes "snes/Thumbs.db"
recognized_file snes "snes/.DS_Store"
recognized_file snes "snes/lista giochi.txt"

for ((i = 0; i < 2 * MULT; i++)); do
    make_game; pick_ext ps2; ext_of "x$EXT"
    recognized_file ps2 "ps2/$GAME/$GAME$EXT"
    [ "$EXT_L" = ".bin" ] && recognized_file ps2 "ps2/$GAME/$GAME.cue"
    rnd 2; [ "$R" -eq 0 ] && recognized_file ps2 "ps2/$GAME/cover.jpg"
done
for ((i = 0; i < MULT; i++)); do
    make_title; make_tag
    recognized_file ps2 "ps2/$TITLE$TAG/$TITLE$TAG (Disc 1).iso"
    recognized_file ps2 "ps2/$TITLE$TAG/$TITLE$TAG (Disc 2).iso"
    recognized_file ps2 "ps2/$TITLE$TAG/$TITLE$TAG.m3u"
done
make_game; recognized_file ps2 "ps2/$GAME.iso" DUPLICATE

for ((i = 0; i < 3 * MULT; i++)); do
    make_game; rnd 2
    if [ "$R" -eq 0 ]; then ext=.iso; else ext=.cso; fi
    rnd 2
    if [ "$R" -eq 0 ]; then recognized_file psp "psp/$GAME$ext"; else recognized_file psp "psp/ISO/$GAME$ext"; fi
done

# Console presente nel mapping ma non nello schema: nessun filtro
for ((i = 0; i < 2; i++)); do
    make_game; recognized_file gba "gba/$GAME.gba"
done
recognized_file gba "gba/note.txt"

# ------------------------------------------------------------------------------
# Scenario 2: file sciolti
# ------------------------------------------------------------------------------
for ((i = 0; i < 3 * MULT; i++)); do make_game; pick_ext snes; loose_file "$GAME$EXT"; done
for ((i = 0; i < 3 * MULT; i++)); do
    make_game; rnd 5; ext=.iso; [ "$R" -eq 0 ] && ext=.ISO
    loose_file "$GAME$ext"
done
for ((i = 0; i < MULT; i++)); do make_game; loose_file "$GAME.cso"; done
for ((i = 0; i < MULT; i++)); do
    make_game; rnd 3
    case $R in 0) ext=.chd ;; 1) ext=.img ;; *) ext=.bin ;; esac
    loose_file "$GAME$ext"
done
for ((i = 0; i < 3 * MULT; i++)); do
    make_title; pick JUNK_EXT; loose_file "$TITLE$P"
done

# ------------------------------------------------------------------------------
# Scenario 3: cartelle non riconosciute
# ------------------------------------------------------------------------------
for ((i = 0; i < 2 * MULT; i++)); do
    make_game
    unmatched_folder "$GAME" "$GAME.iso" "cover.jpg" "$GAME.nfo"
done
for ((i = 0; i < MULT; i++)); do
    make_game; pick_ext snes
    unmatched_folder "$GAME" "$GAME$EXT" "$GAME.srm" "info.txt"
done
unmatched_folder "Wallpapers & Artwork" "sfondo 1.jpg" "sfondo 2.png" "Thumbs.db"
make_game; a="$GAME"; make_game; b="$GAME"; make_game; c="$GAME"
unmatched_folder "Mixed Dump" "$a.sfc" "$b.smc" "$c.iso" "note.txt"
make_game; a="$GAME"; make_game; b="$GAME"
unmatched_folder "Snes Backup" "$a.sfc" "$b.zip"
make_title
unmatched_folder "$TITLE Collection" "Disc 1/$TITLE (Disc 1).iso" "Disc 2/$TITLE (Disc 2).iso" "Disc 2/booklet.pdf"

# ------------------------------------------------------------------------------
# Scenario 4: casi limite nei nomi
# ------------------------------------------------------------------------------
loose_file "Dragon's Lair (USA).sfc"
loose_file "Game & Watch Gallery (Japan).smc"
loose_file "Super   Spaced   Out (USA).sfc"
loose_file "-leading dash (USA).iso"
loose_file "Café Mystère (Europe).iso"
loose_file "dotted.name.v1.2.final.sfc"
loose_file "UPPERCASE GAME (USA).ISO"
loose_file "\$5 Bargain Bin (USA).sfc"
loose_file "Tricky [!] (Rev A) (v1.1).smc"
loose_file ".hidden game.sfc"
loose_file "senza_estensione"
loose_file "archivio.tar.gz"
unmatched_folder "Gioco con 'apici' & spazi (Europe)" "Gioco con 'apici' & spazi (Europe).iso" "Gioco con 'apici' & spazi (Europe).cue"

# ------------------------------------------------------------------------------
# Archivio preesistente (giochi gia' presenti che non arrivano dalla sorgente)
# ------------------------------------------------------------------------------
for ((i = 0; i < MULT; i++)); do
    make_game; pick_ext snes; mkf "$ARC/snes/$GAME$EXT"; rec PRE_EXISTING "-" "snes/$GAME$EXT" "-"
    make_game; pick_ext ps2; mkf "$ARC/ps2/$GAME$EXT"; rec PRE_EXISTING "-" "ps2/$GAME$EXT" "-"
done

# ------------------------------------------------------------------------------
# Riepilogo
# ------------------------------------------------------------------------------
echo "Sandbox creata: $OUT"
echo "  seed: $SEED   size: $SIZE   file in sorgente: $(find "$SRC" -type f | wc -l)"
echo
echo "Elementi per categoria (manifest.txt):"
grep -v '^#' "$MANIFEST" | cut -f1 | sort | uniq -c | sed 's/^/  /'
echo
echo "Per provare lo Smart Ingest:"
echo "  cd \"$SCRIPTS\" && bash gamemanager.sh"
echo "  sorgente da inserire: $SRC"
echo "Per rimuovere: bash \"$TOOLS_DIR/$(basename "$0")\" --clean \"$OUT\""
