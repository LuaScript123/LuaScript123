#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  echo 'Ce script cible Linux x86_64. Sur Windows/macOS, installez Rojo 7.7.1 et Luau 0.742 depuis leurs releases officielles.' >&2
  exit 1
fi
mkdir -p "$project_dir/.tools/bin" "$project_dir/.tools/downloads"
install_archive() {
  local archive_name="$1" archive_sha="$2" archive_url="$3"
  local archive_path="$project_dir/.tools/downloads/$archive_name"
  if [[ ! -f "$archive_path" ]]; then
    curl --fail --silent --show-error --location --retry 2 --max-time 120 "$archive_url" -o "$archive_path.tmp"
    mv -- "$archive_path.tmp" "$archive_path"
  fi
  if ! printf '%s  %s\n' "$archive_sha" "$archive_path" | sha256sum --check --status; then
    echo "Archive non conforme : $archive_path. Supprimez-la avant une nouvelle tentative." >&2
    exit 1
  fi
  unzip -oq "$archive_path" -d "$project_dir/.tools/bin"
}
install_archive rojo-7.7.1.zip 00feb4fa0829a1dd72b49df2639da519a352bfe13cadcd83969e2ba2bb5693c4 https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-linux-x86_64.zip
install_archive luau-0.742.zip 152058b98c60ff1f5b5ec9bca0b8eb37793cae161dd3a05608cc3d8738ba1a4d https://github.com/luau-lang/luau/releases/download/0.742/luau-ubuntu.zip
chmod +x "$project_dir/.tools/bin/rojo" "$project_dir/.tools/bin/luau" "$project_dir/.tools/bin/luau-compile" "$project_dir/.tools/bin/luau-analyze"
"$project_dir/.tools/bin/rojo" --version
echo 'Luau 0.742 installe ; archives SHA-256 verifiees.'
