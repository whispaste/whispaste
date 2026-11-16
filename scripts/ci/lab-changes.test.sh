#!/usr/bin/env bash
# Regression tests for fast-lab selection; no validators or lab guest needed.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LAB_AREA_CACHE="$tmp/cache" GITHUB_OUTPUT="$tmp/outputs" LAB_FULL=false
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test
mkdir "$tmp/repo"
cd "$tmp/repo"
git init -q
git config core.autocrlf false
mkdir -p scripts/ci
for helper in packaging-validate linux-native-tests; do
  cp "$root/scripts/ci/$helper.sh" "scripts/ci/$helper.sh"
  git add "scripts/ci/$helper.sh"
done

# Build fixture commits directly, independent of the developer's hooks.
commit() { git update-ref HEAD "$(git commit-tree "$(git write-tree)" -m fixture)"; }
change() {
  mkdir -p "$(dirname "$1")"
  printf 'change\n' >> "$1"
  git add -- "$1"
  commit
}
record() { bash "$root/scripts/ci/lab-changes.sh" record "$1"; }
record_all() { for area in website packaging native_linux dart; do record "$area"; done; }
expect() {
  : > "$GITHUB_OUTPUT"
  bash "$root/scripts/ci/lab-changes.sh" detect > "$tmp/log"
  local area expected
  for area in website packaging native_linux dart; do
    expected=false
    case " $* " in *" $area "*) expected=true ;; esac
    if ! grep -qx "$area=$expected" "$GITHUB_OUTPUT"; then
      echo "FAIL: expected $area=$expected" >&2
      cat "$tmp/log" "$GITHUB_OUTPUT" >&2
      exit 1
    fi
    if [ "$expected" = false ]; then
      grep -q "LAB-SKIP $area: inputs unchanged since successful check" "$tmp/log"
    fi
  done
}

commit
expect website packaging native_linux dart # First run has no successful baseline.
record_all
expect
change internal-notes
expect

# Every validator input participates, including shared Windows C++ helpers.
for pair in 'packaging packaging-validate' 'native_linux linux-native-tests'; do
  read -r area helper <<< "$pair"
  inputs=$(bash "$root/scripts/ci/$helper.sh" --inputs)
  while IFS= read -r input; do
    # Scripts remain executable Bash for the next dependency-list lookup.
    case "$input" in scripts/ci/*.sh) content='# fixture change' ;;
      *) content=fixture ;;
    esac
    case "$input" in */|packaging) input="${input%/}/fixture" ;; esac
    mkdir -p "$(dirname "$input")"
    printf '%s\n' "$content" >> "$input"
    git add -- "$input"
    commit
    # Validator inputs under the analysed Dart paths also select dart.
    case "$input" in lib/*|test/*|integration_test/*|tool/*|generators/*|benchmarks/*|packages/*)
      expect "$area" dart; record dart ;;
      *) expect "$area" ;;
    esac
    record "$area"
    expect
  done <<< "$inputs"
done

for input in website/src/example.ts design-tokens/example.json .nvmrc .node-version; do
  change "$input"
  expect website
  record website
done
# App sources shared with the website drift guards select both.
for input in lib/core/config/whisper_languages.dart lib/services/model_download_service.dart \
  lib/services/stt_parakeet/parakeet_model_registry.dart \
  lib/services/stt_parakeet/parakeet_gguf_model.dart; do
  change "$input"
  expect website dart
  record website
  record dart
done
# Everything flutter analyze reads (#1403).
for input in lib/x.dart test/x_test.dart integration_test/x.dart tool/x.dart generators/x.dart \
  benchmarks/x.dart packages/p/lib/p.dart pubspec.yaml pubspec.lock analysis_options.yaml .flutter-version; do
  change "$input"
  expect dart
  record dart
done

change website/src/example.ts
change internal-notes # A superseded push must not hide the website change.
expect website
expect website # No record after a failure: the next attempt still runs.
record website
git mv website/src/example.ts website/src/renamed.ts
commit
expect website
record website
git rm -q website/src/renamed.ts
commit
expect website
record website
expect

printf 'corrupt\n' > "$LAB_AREA_CACHE/packaging"
expect packaging
record packaging
LAB_FULL=true expect website packaging native_linux dart
expect
for input in .internal forge/workflows/lab.yml scripts/ci/lab-changes.sh \
  scripts/ci/lab-changes.test.sh .gitattributes; do
  change "$input"
  expect website packaging native_linux dart
  record_all
done
echo 'lab-changes: all selection, cache and retry tests passed'
