#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
path="$root/runtime/media-mount/kpi/.nextgen-media-test-$$"
trap 'test ! -e "$path.renamed" || mv "$path.renamed" "$path.deleted"; test ! -e "$path.deleted" || unlink "$path.deleted"' EXIT
printf 'kobo-media-test' > "$path"
[[ $(cat "$path") == kobo-media-test ]]
mv "$path" "$path.renamed"
[[ $(cat "$path.renamed") == kobo-media-test ]]
mv "$path.renamed" "$path.deleted"
unlink "$path.deleted"
echo 'media create/read/rename/delete passed'
