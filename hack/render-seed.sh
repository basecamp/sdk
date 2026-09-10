#!/usr/bin/env bash
# Renders seed/ into OUT_DIR the way prompts/seed-sdk.md describes: fill every
# {{.Var}} placeholder in a .tmpl file, strip the .tmpl extension, copy every other
# file verbatim. Fails if any placeholder survives, which is also how an
# undocumented placeholder gets caught: the fixture below fills exactly the set
# AGENTS.md lists as in use.
#
# Usage: hack/render-seed.sh OUT_DIR
set -euo pipefail

out="${1:?usage: hack/render-seed.sh OUT_DIR}"
seed="$(cd "$(dirname "$0")/../seed" && pwd)"

# Pipelines first so the bare placeholder patterns do not eat their prefixes.
substitutions=(
  's/{{\.AppName | upper}}/FIZZY/g'
  's/{{\.RubyGem | snakecase}}/fizzy_sdk/g'
  's/{{\.AppTitle}}/Fizzy/g'
  's/{{\.AppName}}/fizzy/g'
  's/{{\.AppLower}}/fizzy/g'
  's/{{\.SwiftPackage}}/Fizzy/g'
  's/{{\.KotlinPackage}}/fizzy-sdk/g'
  's/{{\.RubyModule}}/Fizzy/g'
  's/{{\.RubyGem}}/fizzy-sdk/g'
  's#{{\.ModulePath}}#github.com/basecamp/fizzy-sdk#g'
  's#{{\.NpmPackage}}#@basecamp/fizzy#g'
  's/{{\.NpmScope}}/@basecamp/g'
  's/{{\.GithubOrg}}/basecamp/g'
  's/{{\.GithubRepo}}/fizzy-sdk/g'
)
sed_args=()
for s in "${substitutions[@]}"; do
  sed_args+=(-e "$s")
done

mkdir -p "$out"
rendered=0
copied=0
while IFS= read -r -d '' src; do
  rel="${src#"$seed"/}"
  dest="$out/$rel"
  mkdir -p "$(dirname "$dest")"
  if [[ "$src" == *.tmpl ]]; then
    sed "${sed_args[@]}" "$src" > "${dest%.tmpl}"
    [ ! -x "$src" ] || chmod +x "${dest%.tmpl}"
    rendered=$((rendered + 1))
  else
    cp "$src" "$dest"
    copied=$((copied + 1))
  fi
done < <(find "$seed" -type f -print0)

echo "Rendered $rendered templates and copied $copied files into $out"

set +e
leftovers=$(grep -rnE '\{\{-?[[:space:]]*\.' "$out")
grep_status=$?
set -e
case "$grep_status" in
  1) ;;
  0)
    echo "Placeholders left unrendered (undocumented in AGENTS.md, or in a non-.tmpl file):"
    echo "$leftovers"
    exit 1
    ;;
  *)
    echo "grep failed with status $grep_status while checking $out"
    exit "$grep_status"
    ;;
esac
