#!/usr/bin/env bash
# Privacy gate for PUBLIC repos (play, contracts). Scans git-TRACKED files for
# secrets and proprietary tuning. Exit 1 (block) on any finding. Wired as a
# pre-push hook (scripts/githooks/pre-push); also runnable by hand:
#   bash scripts/privacy-check.sh
#
# Rule (per team policy): no env/secrets, private keys, or game formula/strategy
# in a public repo. Canonical secrets live in CF env; design lives in private docs.
set -u
top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "privacy-check: not inside a git repo"; exit 1; }
cd "$top" || exit 1
fail=0
note() { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }

# 1) secret / proprietary FILES that must never be tracked
bad_files=$(git ls-files | grep -iE \
  '(^|/)\.env$|(^|/)\.dev\.vars$|\.hex$|\.key$|\.keypair$|(^|/)id\.json$|(^|/)keypair\.json$|(^|/)shared/private/' \
  || true)
[ -n "$bad_files" ] && note $'secret/proprietary FILE tracked:\n'"$bad_files"

# 2) secret VALUES assigned in tracked content (skip placeholders / env reads / examples)
val=$(git grep -nIE \
  '(PRIVKEY|PRIVATE_KEY|HMAC_SECRET|API_KEY|AUTHORITY_PRIVKEY_HEX|AGENT_CONFIG)[[:space:]]*[:=][[:space:]]*["'\''0-9A-Za-z+/]{12,}' \
  -- . 2>/dev/null | grep -vIE '\.example|process\.env|env\.|<[^>]*>|replace-with|your-' || true)
[ -n "$val" ] && note $'secret VALUE assigned in tracked file:\n'"$val"

# 3) PEM private-key blocks
pem=$(git grep -nI 'BEGIN [A-Z ]*PRIVATE KEY' -- . 2>/dev/null || true)
[ -n "$pem" ] && note $'PEM private key block:\n'"$pem"

# 4) proprietary formula / strategy DATA leaking into a tracked (public) file.
#    Matches config DATA (quoted JSON keys, array literals, omen g numbers) but
#    NOT code that merely READS a config field (e.g. `config.omenTriggerStreak`).
formula=$(git grep -nIE \
  '"(talentWeights|omenTriggerStreak|reinforceEveryTurns|timeScale|maxReinforcements|maxFieldMinions|dPerUse|timeBurnMax|constantC)"[[:space:]]*:|"g"[[:space:]]*:[[:space:]]*-?[0-9]|(TALENT_WEIGHTS|OMEN_BANK)[[:space:]]*=|talentWeights[[:space:]]*[:=][[:space:]]*\[' \
  -- . 2>/dev/null | grep -vIE '(^|/)shared/private/|\.example' || true)
[ -n "$formula" ] && note $'proprietary formula/strategy DATA in tracked file:\n'"$formula"

if [ "$fail" -ne 0 ]; then
  printf '\n\033[31m🚫 privacy-check FAILED — do NOT push.\033[0m Move secrets to CF env / private docs, or gitignore.\n'
  exit 1
fi
printf '\033[32m✓ privacy-check passed\033[0m — no secrets or proprietary tuning in tracked files.\n'
