#!/usr/bin/env bash
# Select optional fast-lab checks by their last successful input tree, not
# the push's before SHA: queued pushes can be superseded without being tested.
# Usage: lab-changes.sh detect | record <website|packaging|native_linux|dart>
# LAB_AREA_CACHE must live outside the checkout (lab-ci cleans the checkout).
# A missing/corrupt cache runs the checks; LAB_FULL=true forces a manual run.
set -euo pipefail

cache="${LAB_AREA_CACHE:?Set LAB_AREA_CACHE to the persistent lab cache directory}"
mode="${1:?Expected detect or record}"
cd "$(git rev-parse --show-toplevel)"

fingerprint() {
  local area="$1" input
  local paths=(.internal forge/workflows/lab.yml scripts/ci/lab-changes.sh
    scripts/ci/lab-changes.test.sh .gitattributes)
  case "$area" in
    website)
      # Website drift guards also read these shared tokens and app registries.
      paths+=(website design-tokens .nvmrc .node-version
        lib/core/config/whisper_languages.dart
        lib/services/model_download_service.dart
        lib/services/stt_parakeet/parakeet_model_registry.dart
        lib/services/stt_parakeet/parakeet_gguf_model.dart)
      ;;
    dart)
      # flutter analyze in lab/ubu (#1403): the analysed paths plus everything that changes their resolution.
      paths+=(lib test integration_test tool generators benchmarks packages
        pubspec.yaml pubspec.lock analysis_options.yaml .flutter-version)
      ;;
    packaging|native_linux)
      local helper=packaging-validate
      [ "$area" != native_linux ] || helper=linux-native-tests
      # Keep the validators' own dependency lists as the source of truth.
      local inputs
      inputs=$(bash "scripts/ci/$helper.sh" --inputs)
      while IFS= read -r input; do
        [ -z "$input" ] || paths+=("${input%/}")
      done <<< "$inputs"
      ;;
    *) echo "lab-changes: unknown area $area" >&2; return 2 ;;
  esac
  # Includes names, modes and blob IDs: additions, deletions and renames count.
  # No history/fetch needed; works even in a shallow checkout after guest reset.
  git ls-tree -r -z HEAD -- "${paths[@]}" | git hash-object --stdin
}

case "$mode" in
  detect)
    for area in website packaging native_linux dart; do
      key=$(fingerprint "$area")
      previous=''
      if [ -r "$cache/$area" ]; then read -r previous < "$cache/$area" || previous=''; fi
      run=true
      if [ "${LAB_FULL:-false}" = true ]; then
        echo "LAB-RUN $area: full run requested"
      elif [ "$previous" = "$key" ]; then
        run=false
        echo "LAB-SKIP $area: inputs unchanged since successful check ($key)"
      else
        echo "LAB-RUN $area: inputs changed or no successful cached check"
      fi
      printf '%s=%s\n' "$area" "$run" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    done
    ;;
  record)
    area="${2:?Expected area}"
    key=$(fingerprint "$area")
    mkdir -p "$cache"
    printf '%s\n' "$key" > "$cache/$area.tmp"
    mv "$cache/$area.tmp" "$cache/$area"
    ;;
  *) echo "lab-changes: expected detect or record" >&2; exit 2 ;;
esac
