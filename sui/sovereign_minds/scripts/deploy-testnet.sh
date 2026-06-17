#!/usr/bin/env bash
# Publish sovereign_minds to Sui testnet (NO multisig — the AdminCap/UpgradeCap
# stay on your active dev address; switch to a multisig only at mainnet).
#
#   bash scripts/deploy-testnet.sh
#
# Optional one-shot: also wire the voucher authority public key (from
# `node backend/scripts/gen-authority-key.mjs`, which prints "pubkey hex : ..."):
#   AUTHORITY_PUBKEY_HEX=06e3...57dd bash scripts/deploy-testnet.sh
#
# Prints the object IDs and the exact lines to paste into backend/.prod.vars.
# No secrets are read or written by this script (the authority PRIVATE key never
# leaves ~/.consss-sovereign-authority.hex / CF secrets).
set -euo pipefail
cd "$(dirname "$0")/.."   # package root (where Move.toml lives)

command -v jq >/dev/null || { echo "need 'jq' (sudo apt install jq)"; exit 1; }
command -v sui >/dev/null || { echo "need the 'sui' CLI"; exit 1; }

echo "▸ switching to testnet ..."
sui client switch --env testnet >/dev/null
echo "  active address: $(sui client active-address)"

echo "▸ publishing (gas budget 0.2 SUI; faucet if you have no gas) ..."
OUT="$(sui client publish --gas-budget 200000000 --json)"

PKG="$(printf '%s' "$OUT"   | jq -r '.objectChanges[] | select(.type=="published") | .packageId')"
REG="$(printf '%s' "$OUT"   | jq -r '.objectChanges[] | select((.objectType? // "") | endswith("::sovereign::SovereignRegistry")) | .objectId')"
ADMIN="$(printf '%s' "$OUT" | jq -r '.objectChanges[] | select((.objectType? // "") | endswith("::sovereign::AdminCap")) | .objectId')"
UPG="$(printf '%s' "$OUT"   | jq -r '.objectChanges[] | select((.objectType? // "") | endswith("::package::UpgradeCap")) | .objectId')"

[ -n "$PKG" ] && [ -n "$REG" ] || { echo "could not parse package/registry from publish output"; echo "$OUT" | head -40; exit 1; }

echo ""
echo "── deployed IDs ──"
echo "  package    : $PKG"
echo "  registry   : $REG"
echo "  AdminCap   : $ADMIN"
echo "  UpgradeCap : $UPG   (keep on your dev key for testnet)"

# Optional: wire the authority public key now.
if [ -n "${AUTHORITY_PUBKEY_HEX:-}" ]; then
  echo ""
  echo "▸ setting authority pubkey ..."
  sui client call --package "$PKG" --module sovereign --function set_authority_pubkey \
    --args "$ADMIN" "$REG" "0x${AUTHORITY_PUBKEY_HEX#0x}" --gas-budget 20000000 >/dev/null
  echo "  ✓ authority pubkey set"
else
  echo ""
  echo "▸ next: wire the authority pubkey (pubkey from backend/scripts/gen-authority-key.mjs):"
  echo "    sui client call --package $PKG --module sovereign --function set_authority_pubkey \\"
  echo "      --args $ADMIN $REG \"0x<PUBKEY_HEX>\" --gas-budget 20000000"
  echo "    (if the 0x form errors, pass the bytes as a JSON array \"[6,227,...]\")"
fi

echo ""
echo "── paste into backend/.prod.vars (gitignored) ──"
echo "  SOVEREIGN_REGISTRY_ID=$REG"
echo "  SOVEREIGN_DEED_TYPE=${PKG}::sovereign::SovereignDeed"
