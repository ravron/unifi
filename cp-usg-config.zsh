#!/usr/bin/env zsh

echo -n 'checking config.gateway.json...'
if ! jq empty config.gateway.json; then
    echo
    echo 'malformed config.gateway.json'
    exit 1
fi
echo 'ok'

echo 'displaying diff against current config.gateway.json...'
git diff --exit-code =(ssh uck.local 'cat /usr/lib/unifi/data/sites/ghyx00gk/config.gateway.json') config.gateway.json
ret=$?
if (( $ret == 128 )); then
    echo 'failed to generate diff'
    exit 1
elif (( $ret == 0 )); then
    echo 'no diff with existing config.gateway.json'
    exit 1
fi
echo -n 'diff ok? [y/N] '
read -k 1
echo
# Flag L lower-cases REPLY
if ! [[ ${(L)REPLY} == y ]]; then
    echo 'aborting'
    exit 1
fi

scp config.gateway.json uck.local:/usr/lib/unifi/data/sites/ghyx00gk

echo 'you may wish to force a provision of affected devices'
