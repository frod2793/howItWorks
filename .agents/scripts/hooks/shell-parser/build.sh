#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then echo 'usage: build.sh arm64|x86_64|universal ABSENT_ABSOLUTE_OUTPUT' >&2; exit 2; fi
ARCH=$1
OUT=$2
case "$ARCH" in arm64|x86_64) ARCHES=$ARCH;; universal) ARCHES='arm64 x86_64';; *) exit 2;; esac
case "$OUT" in /*) ;; *) echo 'output must be absolute' >&2; exit 2;; esac
if [ -e "$OUT" ] || [ -L "$OUT" ]; then echo 'output already exists' >&2; exit 4; fi
PKG=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
BUILD=$(mktemp -d "$(dirname "$OUT")/.tsparse-build.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
python3 - "$PKG" "$BUILD" <<'PY'
import hashlib, json, pathlib, sys, tarfile
pkg, dest = map(pathlib.Path, sys.argv[1:])
manifest = json.loads((pkg / 'manifest.json').read_text(encoding='utf-8'))
for name, expected in manifest['package_files'].items():
    actual = hashlib.sha256((pkg / name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit('package SHA mismatch: ' + name)
archive = pkg / 'sources.tar.gz'
if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['archive_sha256']:
    raise SystemExit('archive SHA mismatch')
expected = manifest['source_files']
with tarfile.open(archive, 'r:gz') as tar:
    members = tar.getmembers()
    if len(members) != len(expected):
        raise SystemExit('archive member count mismatch')
    total = 0
    seen = set()
    for member in members:
        parts = pathlib.PurePosixPath(member.name).parts
        if (not member.isfile() or member.name in seen or member.name not in expected
                or not parts or any(x in ('', '.', '..') for x in parts)
                or member.name.startswith('/') or '\\' in member.name
                or member.size > 50 * 1024 * 1024):
            raise SystemExit('unsafe archive member: ' + member.name)
        seen.add(member.name)
        total += member.size
        if total > 100 * 1024 * 1024:
            raise SystemExit('archive uncompressed size limit')
        data = tar.extractfile(member).read()
        if hashlib.sha256(data).hexdigest() != expected[member.name]:
            raise SystemExit('archive member SHA mismatch: ' + member.name)
        target = dest.joinpath(*parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as stream:
            stream.write(data)
    if seen != set(expected):
        raise SystemExit('archive member set mismatch')
PY
for THIN_ARCH in $ARCHES; do
/usr/bin/clang -arch "$THIN_ARCH" -O2 -std=c11 -mmacosx-version-min=11.0 \
  -I"$BUILD/core/lib/include" -I"$BUILD/core/lib/src" \
  -I"$BUILD/bash/src" -I"$BUILD/zsh/src" \
  "$PKG/tsparse.c" "$BUILD/core/lib/src/lib.c" \
  "$BUILD/bash/src/parser.c" "$BUILD/bash/src/scanner.c" \
  "$BUILD/zsh/src/parser.c" "$BUILD/zsh/src/scanner.c" \
  -o "$BUILD/tsparse-$THIN_ARCH"
done
if [ "$ARCH" = universal ]; then
  /usr/bin/lipo -create "$BUILD/tsparse-arm64" "$BUILD/tsparse-x86_64" -output "$BUILD/tsparse-universal"
fi
ln "$BUILD/tsparse-$ARCH" "$OUT"
