#!/bin/bash
set -euo pipefail

[[ "${PLATFORM_NAME}" == "macosx" ]] || exit 0
[[ "${SKIP_DNSDECK_MCP_BUILD:-NO}" != "YES" ]] || exit 0

configuration=debug
[[ "${CONFIGURATION}" != "Release" ]] || configuration=release

arguments=(--package-path "${SRCROOT}" --scratch-path "${DERIVED_FILE_DIR}/DNSDeckMCPBuild" -c "${configuration}")
read -r -a architectures <<< "${ARCHS}"
for architecture in "${architectures[@]}"; do
    arguments+=(--arch "${architecture}")
done

swift build "${arguments[@]}" --product DNSDeckMCP
bin_path="$(swift build "${arguments[@]}" --show-bin-path)"
destination="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/DNSDeckMCP"
resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$(dirname "${destination}")" "${resources}"
install -m 755 "${bin_path}/DNSDeckMCP" "${destination}"
ditto "${bin_path}/DNSDeckMCP_DNSDeckMCP.bundle" "${resources}/DNSDeckMCP_DNSDeckMCP.bundle"

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
        --entitlements "${SRCROOT}/${CODE_SIGN_ENTITLEMENTS}" --timestamp=none "${destination}"
fi
