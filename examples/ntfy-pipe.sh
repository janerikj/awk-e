#!/usr/bin/env bash
# examples/ntfy-pipe.sh - ntfy -> awk-e recipe.
#
# Subscribes to a topic's JSON stream and prints each message as an awk-e
# "topic payload" line. The stream is long-lived, so run it without --every:
#
#     awk-e --pipe './examples/ntfy-pipe.sh mytopic'
#
# ntfy.sh topics are public by default. Use an unguessable topic, or a
# self-hosted server with NTFY_URL together with NTFY_USER/NTFY_PASS or
# NTFY_TOKEN.
#
# curl and jq are not dependencies of awk-e, only of this recipe:
#     sudo apt install curl jq
set -uo pipefail

usage() {
    cat <<EOF
ntfy-pipe.sh - ntfy -> awk-e recipe

usage: ntfy-pipe.sh [-?|--help] [TOPIC]

Subscribes to TOPIC's JSON stream and prints each message as an awk-e
"topic payload" line, prefixed with NTFY_PREFIX (default ntfy):

    awk-e --pipe './examples/ntfy-pipe.sh mytopic'

TOPIC  ntfy topic (or NTFY_TOPIC)
       ntfy.sh topics are public unless you self-host or authenticate.

NTFY_URL     server base URL (default https://ntfy.sh)
NTFY_PREFIX  topic prefix (default ntfy)
NTFY_USER    basic-auth user
NTFY_PASS    basic-auth password
NTFY_TOKEN   bearer token; wins over NTFY_USER/NTFY_PASS
NTFY_SINCE   replay from an ntfy since= value, then keep streaming
CURL, JQ     binaries to run, for testing

  -?, --help   show this help and exit
EOF
}

posargs=()
while (( $# )); do
    case $1 in
        -\?|--help) usage; exit 0 ;;
        -*) printf 'ntfy-pipe.sh: unknown option: %s\n' "$1" >&2; exit 2 ;;
        *) posargs+=("$1"); shift ;;
    esac
done

url=${NTFY_URL:-https://ntfy.sh}
topic=${posargs[0]:-${NTFY_TOPIC:-}}
prefix=${NTFY_PREFIX:-ntfy}
curl_bin=${CURL:-curl}
jq_bin=${JQ:-jq}

[[ -n $topic ]] || { printf 'ntfy-pipe.sh: need TOPIC (or NTFY_TOPIC)\n' >&2; exit 2; }
[[ $topic =~ ^[-_A-Za-z0-9]{1,64}$ ]] ||
    { printf 'ntfy-pipe.sh: invalid topic: %s\n' "$topic" >&2; exit 2; }
[[ $url =~ ^https?:// ]] ||
    { printf 'ntfy-pipe.sh: NTFY_URL must start with http:// or https://: %s\n' "$url" >&2; exit 2; }
command -v "$curl_bin" >/dev/null 2>&1 ||
    { printf 'ntfy-pipe.sh: curl not found (sudo apt install curl)\n' >&2; exit 1; }
command -v "$jq_bin" >/dev/null 2>&1 ||
    { printf 'ntfy-pipe.sh: jq not found (sudo apt install jq)\n' >&2; exit 1; }

url=${url%/}
stream=$url/$topic/json
[[ -n ${NTFY_SINCE:-} ]] && stream+="?since=$NTFY_SINCE"

args=(-fsSN --connect-timeout 10 --retry 5 --retry-delay 5 --retry-connrefused)
if [[ -n ${NTFY_TOKEN:-} ]]; then
    args+=(-H "Authorization: Bearer $NTFY_TOKEN")
elif [[ -n ${NTFY_USER:-} ]]; then
    args+=(-u "$NTFY_USER:${NTFY_PASS:-}")
fi
args+=("$stream")

# curl and jq are joined through a fifo so both pids stay reachable on shutdown.
umask 077
fifo=$(mktemp -u "${TMPDIR:-/tmp}/awk-e.ntfy.XXXXXX") ||
    { printf 'ntfy-pipe.sh: mktemp failed\n' >&2; exit 1; }
mkfifo "$fifo" || { rm -f "$fifo"; printf 'ntfy-pipe.sh: mkfifo failed\n' >&2; exit 1; }

curl_pid=""
jq_pid=""

cleanup() {
    [[ -n $jq_pid ]] && kill "$jq_pid" 2>/dev/null
    [[ -n $curl_pid ]] && kill "$curl_pid" 2>/dev/null
    [[ -n $jq_pid ]] && wait "$jq_pid" 2>/dev/null
    [[ -n $curl_pid ]] && wait "$curl_pid" 2>/dev/null
    rm -f "$fifo"
    return 0
}
trap 'cleanup; exit 0' TERM INT HUP

"$curl_bin" "${args[@]}" > "$fifo" &
curl_pid=$!
"$jq_bin" --unbuffered -r --arg prefix "$prefix" '
    select(.event == "message") |
    (.message // "") as $message |
    "\($prefix)/\(.topic) " +
        ($message | tostring |
            gsub("\r\n"; "\\n") |
            gsub("\r"; "\\r") |
            gsub("\n"; "\\n"))
' < "$fifo" &
jq_pid=$!

wait "$jq_pid"
rc=$?
cleanup
exit "$rc"
