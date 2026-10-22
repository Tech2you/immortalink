#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd -- "${0:A:h}"

print 'Heiro Safety Review'
print 'Keep this window open while reviewing. Close it when finished.'
print 'Only use this launcher on your authorized Mac. Do not share its private link.'
for dependency in node supabase; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    print "Cannot start: $dependency is unavailable. No report decision was made."
    read -r '?Press Return to close.'
    exit 1
  fi
done
if node scripts/content_review_server.mjs --reviewer 'Ross Strauss' --open; then
  print 'Review session ended. Double-click this launcher for a new session.'
else
  print 'The review page could not start. Reports remain in the review queue.'
fi
read -r '?Press Return to close.'
