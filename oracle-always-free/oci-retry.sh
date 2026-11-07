#!/usr/bin/env bash
# Versucht freeInstance0 und freeInstance1 so lange zu erstellen, bis beide laufen.
# Probiert dabei alle Availability Domains durch und merkt sich die passende AD
# in ad.auto.tfvars, damit Terraform die Instanz spaeter nicht ersetzt.
#
# Aufruf im Ordner, in dem du sonst terraform ausfuehrst:
#   ./oci-retry.sh
#   INTERVAL=300 ./oci-retry.sh     # Wartezeit pro Durchlauf in Sekunden
#
# Der Load Balancer wird bewusst nicht angelegt. Danach: terraform apply

set -u

INTERVAL="${INTERVAL:-120}"       # Pause nach einem Durchlauf ueber alle ADs
RATE_LIMIT_WAIT=600               # Pause, wenn Oracle zu viele Anfragen meldet
ADS="1 2 3"                       # eu-frankfurt-1 hat drei ADs
INSTANCES="0 1"
TFVARS="ad.auto.tfvars"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

save_ad() {
  local key="instance$1_ad" tmp
  tmp="$(mktemp)"
  [ -f "$TFVARS" ] && grep -v "^$key " "$TFVARS" > "$tmp"
  echo "$key = $2" >> "$tmp"
  mv "$tmp" "$TFVARS"
}

# Instanz steht im State und ist nicht als defekt (tainted) markiert
exists() {
  local out
  out="$(terraform state show -no-color "oci_core_instance.free_instance$1" 2>/dev/null)" || return 1
  case "$out" in
    *tainted*) return 1 ;;
    *) return 0 ;;
  esac
}

# Rueckgabe: 0 = erstellt, 1 = keine Kapazitaet, 2 = Rate Limit, 3 = anderer Fehler
create() {
  terraform apply -auto-approve -input=false -no-color \
    -target="oci_core_instance.free_instance$1" \
    -var "instance$1_ad=$2" > "$LOG" 2>&1 && return 0

  if grep -qiE 'out of (host )?capacity' "$LOG"; then return 1; fi
  if grep -qiE 'TooManyRequests|too many requests|429-' "$LOG"; then return 2; fi
  return 3
}

command -v terraform > /dev/null || { echo "terraform wurde nicht gefunden." >&2; exit 1; }

attempt=0
for i in $INSTANCES; do
  while ! exists "$i"; do
    for ad in $ADS; do
      attempt=$((attempt + 1))
      log "Versuch $attempt: freeInstance$i in AD-$ad"
      create "$i" "$ad"
      case $? in
        0)
          save_ad "$i" "$ad"
          log "freeInstance$i wurde in AD-$ad erstellt."
          break
          ;;
        1)
          log "Keine Kapazitaet in AD-$ad."
          ;;
        2)
          log "Rate Limit erreicht, warte $RATE_LIMIT_WAIT Sekunden."
          sleep "$RATE_LIMIT_WAIT"
          ;;
        3)
          log "Unerwarteter Fehler, Skript stoppt:"
          tail -n 25 "$LOG"
          exit 1
          ;;
      esac
    done
    exists "$i" || sleep "$INTERVAL"
  done
  log "freeInstance$i ist vorhanden."
done

log "Fertig. Pruefe jetzt mit 'terraform plan' und starte dann 'terraform apply' fuer den Load Balancer."
