#!/bin/bash
# roseshell:hidden=true

# Prints the current UTC offset (minutes) and abbreviation for each IANA
# zone named on argv, one compact JSON object per line (not a JSON array —
# that keeps a partial/bad batch trivially parseable line-by-line instead of
# needing to reparse the whole thing on one bad entry):
#   {"zone":"Asia/Tokyo","offsetMinutes":540,"abbr":"JST"}
#   {"zone":"Bogus/Zone","error":true}
#
# `date` reads the offset from the system's own zoneinfo database, so this
# is DST-correct for "right now" without this script knowing anything about
# DST rules itself. Offsets only change at DST transitions, so the caller
# only needs to re-run this occasionally, not every tick.
set -uo pipefail

for zone in "$@"; do
  # IANA zone names are always Area/Location (letters, digits, _, -, +, /
  # only). Reject anything else outright, before it ever reaches a file
  # path or TZ= -- zone names round-trip through shell.json, so a
  # hand-edited file is untrusted input same as any other.
  if [[ ! $zone =~ ^[A-Za-z0-9_+/-]+$ || $zone == *..* ]]; then
    jq -nc --arg zone "$zone" '{zone: $zone, error: true}'
    continue
  fi

  # An unrecognized TZ value doesn't make `date` fail -- glibc just falls
  # back to treating it as a literal (broken) POSIX TZ spec and prints a
  # bogus but non-empty result. Only trust names that are real zoneinfo
  # entries.
  if [[ ! -f "/usr/share/zoneinfo/$zone" ]]; then
    jq -nc --arg zone "$zone" '{zone: $zone, error: true}'
    continue
  fi

  reading=$(TZ="$zone" date +"%z %Z" 2>/dev/null)
  if [[ -z $reading ]]; then
    jq -nc --arg zone "$zone" '{zone: $zone, error: true}'
    continue
  fi

  offset="${reading%% *}"
  abbr="${reading#* }"
  sign="${offset:0:1}"
  hh="${offset:1:2}"
  mm="${offset:3:2}"
  total=$(( 10#$hh * 60 + 10#$mm ))
  [[ $sign == "-" ]] && total=$(( -total ))

  jq -nc --arg zone "$zone" --argjson offsetMinutes "$total" --arg abbr "$abbr" \
    '{zone: $zone, offsetMinutes: $offsetMinutes, abbr: $abbr}'
done
