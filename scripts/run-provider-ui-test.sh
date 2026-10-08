#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <test-class> <provider-name>" >&2
  exit 64
fi

test_class="$1"
provider_name="$2"

if [[ ! "$test_class" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Invalid UI-test class: $test_class" >&2
  exit 64
fi
if [[ ! "$provider_name" =~ ^[A-Z0-9_]+$ ]]; then
  echo "Invalid UI-test provider name: $provider_name" >&2
  exit 64
fi

credentials_key="PROVIDER_${provider_name}_CREDENTIALS"
zone_key="PROVIDER_${provider_name}_ZONE"
environment_keys=("$credentials_key" "$zone_key")
credential_keys=("$credentials_key")

for key in "${environment_keys[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required UI-test environment key: $key" >&2
    exit 78
  fi
done

/usr/bin/python3 - "${credential_keys[@]}" <<'PY'
import json
import os
import sys

for credentials_key in sys.argv[1:]:
    try:
        credentials = json.loads(os.environ[credentials_key])
    except (KeyError, json.JSONDecodeError):
        raise SystemExit(f"{credentials_key} must contain a valid JSON object.")

    if not isinstance(credentials, dict):
        raise SystemExit(f"{credentials_key} must contain a JSON object.")
PY

selector="DNSDeckUITests/$test_class"

xcodebuild build-for-testing \
  -quiet \
  -hideShellScriptEnvironment \
  -project DNSDeck.xcodeproj \
  -scheme "DNSDeck macOS" \
  -destination "platform=macOS" \
  -only-testing:"$selector"

build_dir="$(
  xcodebuild -showBuildSettings \
    -quiet \
    -hideShellScriptEnvironment \
    -project DNSDeck.xcodeproj \
    -scheme "DNSDeck macOS" \
    | awk -F ' = ' '/^[[:space:]]*BUILD_DIR = / { print $2; exit }'
)"
source_xctestrun="$(
  find "$build_dir" -maxdepth 1 -name '*.xctestrun' \
    ! -name 'DNSDeckProviderUITests-*' -print -quit
)"
if [[ -z "$source_xctestrun" ]]; then
  echo "Xcode did not produce an xctestrun file." >&2
  exit 1
fi

run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
xctestrun="$build_dir/DNSDeckProviderUITests-$run_id.xctestrun"
results_root="${DNSDECK_UI_TEST_RESULTS_DIR:-$PWD/test-results/dnsdeck}"
mkdir -p "$results_root"
results_root="$(cd "$results_root" && pwd)"
result_bundle="$results_root/$test_class-$run_id.xcresult"
cp "$source_xctestrun" "$xctestrun"
cleanup() {
  rm -f -- "$xctestrun"
  if [[ -d "$result_bundle" ]]; then
    echo "Result bundle: $result_bundle"
  fi
}
trap cleanup EXIT

chmod 600 "$xctestrun"
/usr/bin/python3 - "$xctestrun" "${environment_keys[@]}" <<'PY'
import os
import plistlib
import sys

path, *keys = sys.argv[1:]
with open(path, "rb") as source:
    document = plistlib.load(source)

targets = [
    target
    for configuration in document.get("TestConfigurations", [])
    for target in configuration.get("TestTargets", [])
]
if not targets:
    raise SystemExit("The xctestrun file has no test targets.")

values = {key: os.environ[key] for key in keys}
for target in targets:
    target.setdefault("EnvironmentVariables", {}).update(values)

with open(path, "wb") as destination:
    plistlib.dump(document, destination)
os.chmod(path, 0o600)
PY

xcodebuild test-without-building \
  -quiet \
  -hideShellScriptEnvironment \
  -xctestrun "$xctestrun" \
  -resultBundlePath "$result_bundle" \
  -destination "platform=macOS" \
  -only-testing:"$selector"
