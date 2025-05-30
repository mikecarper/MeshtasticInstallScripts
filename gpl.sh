#!/usr/bin/env bash
set -euo pipefail

IGNORE_ORG=meshtastic
GITHUB_USER=
GITHUB_TOKEN=

# -----------------------------------------------------------------------------
# fetch_search_array <kind> <query> <outfile>
#
#  kind     = "commits" or "code"  
#  query    = the GitHub search query (no URL-encoding)  
#  outfile  = path to write the JSON array to  
#
#  Uses the GitHub API to page through all hits, streams each item
#  into jq, then writes a single JSON array.  Skips if <outfile> exists.
# -----------------------------------------------------------------------------
fetch_search_array() {
  local kind="$1"
  local query="$2"
  local outfile="$3"

  # pick the right API path and Accept header
  local path accept
  if [[ "$kind" == "commits" ]]; then
    path="search/commits"
    accept="application/vnd.github.cloak-preview"
  else
    path="search/code"
    accept="application/vnd.github.v3+json"
  fi

  if [[ -f "$outfile" ]]; then
    echo "$outfile exists; skipping."
    return
  fi

  echo "Searching for $kind that contain $query"
  local page=1

  # stream each ".items[]" from every page
  (
    while :; do
      resp=$(curl -s \
        -H "Accept: $accept" \
        -u "$GITHUB_USER:$GITHUB_TOKEN" \
        "https://api.github.com/$path?q=${query// /+}+-org:${IGNORE_ORG}&per_page=100&page=$page")

      local count
      count=$(jq '.items | length' <<<"$resp")
      (( count == 0 )) && break

      jq -c '.items[]' <<<"$resp"
      ((page++))
    done
  ) | jq -s '.' > "$outfile"

  echo "Wrote $outfile (total items: $(jq length "$outfile"))"
}

fetch_search_array commits "meshtastic/protobufs"          commits_array.json
fetch_search_array code    "Meshtastic.Protobufs"          results_array.json
fetch_search_array code    "Config.LoRaConfig.ModemPreset" modempreset_array.json
fetch_search_array code    "Config.LoRaConfig.RegionCode"  regioncode_array.json
fetch_search_array code    "proto::meshtastic"             protomeshtastic_array.json
fetch_search_array code    "protobufs/meshtastic"          protobufsmeshtastic_array.json

# —————————————
# Extract, sort & dedupe repos
# —————————————
jq -r '.[].repository.full_name' \
  commits_array.json \
  results_array.json \
  modempreset_array.json \
  regioncode_array.json \
  protomeshtastic_array.json \
  protobufsmeshtastic_array.json \
  | sort -u > repos.txt
echo "Found $(wc -l < repos.txt) unique repos"


mkdir -p licenses
while read -r repo; do
  license_file="licenses/${repo//\//_}.json"

  # only fetch if we haven't already
  if [[ ! -e "$license_file" ]]; then
    printf "\rFetching license for %-50s" "$repo" >/dev/tty

    http_code=$(
      curl -s -w '%{http_code}' \
           -H "Accept: application/vnd.github.v3+json" \
           -u "$GITHUB_USER:$GITHUB_TOKEN" \
           "https://api.github.com/repos/$repo/license" \
           -o "$license_file"
    )

    if [[ "$http_code" == "404" ]]; then
      # no license file → record NONE
      echo '{"license":null}' > "$license_file"
    fi
  else
    printf "\rSkipping %-50s" "$repo" >/dev/tty
  fi
done < repos.txt
printf "\r%65s" >/dev/tty
echo ""

# extract spdx_id (or “null”)
jq -r '.license.spdx_id // "NONE"' licenses/*.json > all_spdx.txt

# list repos that are NOT GPL v3, including “NONE”
paste repos.txt all_spdx.txt \
| awk '$2 !~ /^GPL-3\.0(-only|-or-later)?$/ {
    printf("https://github.com/%s has license: %s\n", $1, $2)
}'
