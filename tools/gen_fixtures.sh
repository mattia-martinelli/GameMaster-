#!/bin/bash

# Compatibilita': l'implementazione e' mantenuta nella root del repository.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$SCRIPT_DIR/gen_fixtures.sh" "$@"
