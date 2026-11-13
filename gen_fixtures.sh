#!/bin/bash

# ===============================================================================
# GENERATORE DI FIXTURE PER LO SMART INGEST
# Crea una sandbox con file vuoti (0 byte) e un manifest con l'esito atteso.
# Non tocca ambiente.env, archivio o ROM reali.
# ===============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"
GM_DIR="$SCRIPT_DIR"
SCHEMA="$GM_DIR/archive_schema.json"
MARKER=".gm-fixture"

