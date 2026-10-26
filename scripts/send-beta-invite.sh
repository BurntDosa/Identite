#!/bin/zsh
# Sends the TestFlight invitation in docs/email/beta-invitation.html through Resend.
# Usage: scripts/send-beta-invite.sh [person@example.com ...]; with no address, it uses the one on the clipboard.
# Key: Keychain item "resend-identite" (security add-generic-password -a "$USER" -s resend-identite -w), or RESEND_API_KEY.
set -euo pipefail
setopt extended_glob

testflight="https://testflight.apple.com/join/BfXC6gb1"
from="Identité Beta <beta@burntdosa.site>"
subject="You're invited to test Identité"

fail() { print -u2 "send-beta-invite: $1"; exit 1; }
(( $# )) || set -- ${(f)"$(pbpaste)"}
(( $# )) || fail "no address given or on the clipboard"
[[ -n $testflight ]] || fail "set testflight in this script first"
key=${RESEND_API_KEY:-$(security find-generic-password -s resend-identite -w 2>/dev/null || true)}
[[ -n $key ]] || fail "no Resend key in Keychain or RESEND_API_KEY"
html=$(<"${0:A:h}/../docs/email/beta-invitation.html")  # :A follows the ~/.local/bin symlink
html=${html//\{\{TESTFLIGHT_URL\}\}/$testflight}
text="Hi there,

You are invited to test Identité, an app that keeps your Indian IDs and bank cards as text you can copy, on iPhone and Mac.

1. Get TestFlight: https://apps.apple.com/app/testflight/id899247664
2. Join the Identité Beta on your iPhone or Mac: $testflight

Your IDs stay on your devices and your private iCloud. I cannot see any of it.

- Gagan"

for to in "$@"; do
  to=${${to##[[:space:]]#}%%[[:space:]]#}
  [[ $to =~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' ]] || fail "not an email address: $to"
  body=$(FROM=$from TO=$to SUBJECT=$subject HTML=$html TEXT=$text python3 -I -c '
import json, os
print(json.dumps({"from": os.environ["FROM"], "to": [os.environ["TO"]], "subject": os.environ["SUBJECT"],
                  "html": os.environ["HTML"], "text": os.environ["TEXT"]}))')
  # The idempotency key stops a re-run from sending the same person a second copy within 24 hours.
  # The key goes in through stdin so it never shows up in the process list.
  print -r -- "Authorization: Bearer $key" | curl -sS --fail-with-body https://api.resend.com/emails \
    -H @- -H 'Content-Type: application/json' \
    -H "Idempotency-Key: identite-invite:$to" -d "$body" >/dev/null || fail "Resend rejected $to"
  print "Sent to $to"
done
