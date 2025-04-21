#!/bin/bash

set -euo pipefail

SELF="${BASH_SOURCE[0]}"
SELF="$(realpath -ms "$SELF")"
cd "$(dirname "$SELF")" || exit 99

find . -not -iname '*.tgz' -and -not -ipath '*examples*' -printf '%P\0' \
| cpio -o -H ustar -0 \
| gzip \
> "$(basename "$PWD").tgz"
# | grep 'examples'
# | tar -czvf "$(basename "$PWD").tgz" --files-from=-
