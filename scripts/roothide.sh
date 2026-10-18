#!/bin/zsh
# Convert a Theos rootless .deb into a roothide one (Procursus roothide / Nyxian jailed):
# files move out of /var/jb, absolute /var/jb rpaths are dropped (the
# @loader_path/.jbroot ones stay), binaries are re-signed, arch -> iphoneos-arm64e,
# hard dependencies on substrate/PreferenceLoader become Recommends.
set -e
IN="$1"; OUT_DIR="${2:-$(dirname "$IN")}"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
dpkg-deb -R "$IN" "$W/pkg"
if [ -d "$W/pkg/var/jb" ]; then
  rsync -a "$W/pkg/var/jb/" "$W/pkg/"; rm -rf "$W/pkg/var/jb"; rmdir "$W/pkg/var" 2>/dev/null || true
fi
find "$W/pkg" -type f ! -path '*/DEBIAN/*' | while read -r f; do
  file -b "$f" | grep -q Mach-O || continue
  for rp in $(otool -l "$f" | awk '/LC_RPATH/{getline;getline;print $2}' | sort -u | grep '^/var/jb'); do
    install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true
  done
  id=$(otool -D "$f" | sed -n 2p)
  case "$id" in /var/jb/*) install_name_tool -id "${id#/var/jb}" "$f";; esac
  ldid -S "$f"
done
C="$W/pkg/DEBIAN/control"
sed -i '' -e 's/^Architecture: .*/Architecture: iphoneos-arm64e/' "$C"
dep=$(grep '^Depends:' "$C" | sed 's/^Depends: *//')
keep=$(echo "$dep" | tr ',' '\n' | sed 's/^ *//' | grep -vE '^(mobilesubstrate|preferenceloader)' | paste -sd, - | sed 's/,/, /g')
rec=$(echo "$dep" | tr ',' '\n' | sed 's/^ *//' | grep -E '^(mobilesubstrate|preferenceloader)' | paste -sd, - | sed 's/,/, /g')
sed -i '' '/^Depends:/d' "$C"
[ -n "$keep" ] && echo "Depends: $keep" >> "$C"
[ -n "$rec" ] && echo "Recommends: $rec" >> "$C"
pkg=$(awk '/^Package:/{print $2}' "$C"); ver=$(awk '/^Version:/{print $2}' "$C")
OUT="$OUT_DIR/${pkg}_${ver}_iphoneos-arm64e.deb"
dpkg-deb -Zxz --root-owner-group -b "$W/pkg" "$OUT" >/dev/null
echo "$OUT"
