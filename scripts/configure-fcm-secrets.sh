#!/usr/bin/env bash
# Configura secretos FCM en Supabase szoyo a partir del JSON de service account
# de Firebase (proyecto creabox-9b1b6).
#
# Uso:
#   ./scripts/configure-fcm-secrets.sh ~/Downloads/creabox-9b1b6-firebase-adminsdk-xxxxx.json
#
# Requisitos: supabase CLI logueada (supabase login)

set -euo pipefail

PROJECT_REF="szoywhtkilgvfrczuyqn"
SA_JSON="${1:-}"

if [[ -z "$SA_JSON" || ! -f "$SA_JSON" ]]; then
  echo "Uso: $0 <ruta-al-service-account.json>"
  echo ""
  echo "Genera el JSON en Firebase Console:"
  echo "  https://console.firebase.google.com/project/creabox-9b1b6/settings/serviceaccounts/adminsdk"
  echo "  → Generar nueva clave privada"
  exit 1
fi

PROJECT_ID=$(python3 -c "import json; print(json.load(open('$SA_JSON'))['project_id'])")
CLIENT_EMAIL=$(python3 -c "import json; print(json.load(open('$SA_JSON'))['client_email'])")
PRIVATE_KEY=$(python3 -c "import json; print(json.load(open('$SA_JSON'))['private_key'])")

if [[ "$PROJECT_ID" != "creabox-9b1b6" ]]; then
  echo "Advertencia: el service account es del proyecto '$PROJECT_ID', no creabox-9b1b6."
  echo "TrazaBox usa google-services.json de creabox-9b1b6; deben coincidir."
  read -r -p "¿Continuar igual? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || exit 1
fi

echo "Configurando secretos en Supabase ($PROJECT_REF)..."
supabase secrets set \
  "FCM_PROJECT_ID=$PROJECT_ID" \
  "FCM_CLIENT_EMAIL=$CLIENT_EMAIL" \
  "FCM_PRIVATE_KEY=$PRIVATE_KEY" \
  --project-ref "$PROJECT_REF"

echo "Listo. Secretos FCM configurados para $PROJECT_ID"
