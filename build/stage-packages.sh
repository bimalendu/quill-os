#!/bin/sh
# Stage packages/ for build-rpms: a copy with the AI denylist added to quill-no-ai
# and quill-setup's src/ tree packed into its source tarball. Used by `make rpms`
# and by CI, so both build the same thing. Works with GNU and BSD tar.
#
#   build/stage-packages.sh OUTDIR     (OUTDIR is emptied first)
set -eu
out=${1:?usage: stage-packages.sh OUTDIR}
cd "$(dirname "$0")/.."
export COPYFILE_DISABLE=1       # no AppleDouble files from macOS tar

rm -rf "$out"; mkdir -p "$out"
cp -R packages/. "$out/"
cp policy/ai-denylist.txt "$out/quill-no-ai/ai-denylist.txt"

t=$(mktemp -d)
mkdir "$t/quill-setup-44"
cp -R packages/quill-setup/src/. "$t/quill-setup-44/"
tar -czf "$out/quill-setup/quill-setup-44.tar.gz" -C "$t" quill-setup-44
rm -rf "$t" "$out/quill-setup/src"
