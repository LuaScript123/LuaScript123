#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
compiler="${LUAU_COMPILE:-$project_dir/.tools/bin/luau-compile}"
runner="${LUAU:-$project_dir/.tools/bin/luau}"
if [[ ! -x "$compiler" || ! -x "$runner" ]]; then
  echo 'Executez bash tools/bootstrap.sh avant les verifications.' >&2
  exit 1
fi
count=0
while IFS= read -r -d '' source_file; do
  "$compiler" --null "$source_file" >/dev/null
  count=$((count + 1))
done < <(find src tests -name '*.luau' -type f -print0)
echo "$count fichiers Luau compiles."
"$runner" tests/CombatRules.spec.luau
"$runner" tests/MatchRules.spec.luau
"$runner" tests/InvitationRules.spec.luau
"$runner" tests/ProfileRules.spec.luau
python3 tools/test-match.py "$runner"
python3 tools/test-profile.py "$runner"
