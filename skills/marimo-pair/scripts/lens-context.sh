#!/usr/bin/env bash
# Read and act on marimo Lens state through execute-code.sh.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  lens-context.sh [TARGET] scan
  lens-context.sh [TARGET] text --revision N --lens-token TOKEN
  lens-context.sh [TARGET] image --selection-id ID --revision N --lens-token TOKEN
  lens-context.sh [TARGET] image --cell CELL --revision N --lens-token TOKEN
  lens-context.sh [TARGET] activity --cell CELL --lens-token TOKEN [--label TEXT] [--message TEXT]
  lens-context.sh [TARGET] reveal --cell CELL --lens-token TOKEN [--message TEXT]
  lens-context.sh [TARGET] resolve ID... --revision N --lens-token TOKEN [--summary TEXT]
  lens-context.sh cleanup-images IMAGE_DIR

TARGET accepts --url URL, --port PORT, --session ID, and --token TOKEN.
EOF
  exit 2
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
execute_script="${script_dir}/execute-code.sh"
python_script="${script_dir}/lens-context.py"
target_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url | --port | --session | --token)
      [[ $# -ge 2 ]] || usage
      target_args+=("$1" "$2")
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

command="${1:-}"
[[ -n "$command" ]] || usage
shift

revision=""
lens_token=""
selection_id=""
cell_id=""
message=""
message_set=false
label=""
label_set=false
summary=""
summary_set=false
positionals=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revision)
      [[ $# -ge 2 && -z "$revision" ]] || usage
      revision="$2"
      shift 2
      ;;
    --lens-token)
      [[ $# -ge 2 && -z "$lens_token" ]] || usage
      lens_token="$2"
      shift 2
      ;;
    --selection-id)
      [[ $# -ge 2 && -z "$selection_id" ]] || usage
      selection_id="$2"
      shift 2
      ;;
    --cell)
      [[ $# -ge 2 && -z "$cell_id" ]] || usage
      cell_id="$2"
      shift 2
      ;;
    --message)
      [[ $# -ge 2 && "$message_set" == false ]] || usage
      message="$2"
      message_set=true
      shift 2
      ;;
    --label)
      [[ $# -ge 2 && "$label_set" == false ]] || usage
      label="$2"
      label_set=true
      shift 2
      ;;
    --summary)
      [[ $# -ge 2 && "$summary_set" == false ]] || usage
      summary="$2"
      summary_set=true
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

case "$command" in
  scan)
    [[ ${#positionals[@]} -eq 0 && -z "$revision$lens_token$selection_id$cell_id" ]] ||
      usage
    [[ "$message_set" == false && "$label_set" == false && "$summary_set" == false ]] ||
      usage
    action="scan"
    args_json="{}"
    ;;
  text)
    [[ ${#positionals[@]} -eq 0 && "$revision" =~ ^[0-9]+$ ]] || usage
    [[ -n "$lens_token" && -z "$selection_id$cell_id" ]] || usage
    [[ "$message_set" == false && "$label_set" == false && "$summary_set" == false ]] ||
      usage
    action="text"
    args_json=$(jq -cn \
      --argjson revision "$revision" \
      --arg lensToken "$lens_token" \
      '{revision: $revision, lensToken: $lensToken}')
    ;;
  image)
    [[ ${#positionals[@]} -eq 0 && -n "$lens_token" ]] || usage
    [[ "$message_set" == false && "$label_set" == false && "$summary_set" == false ]] ||
      usage
    if [[ -n "$selection_id" && -z "$cell_id" && "$revision" =~ ^[0-9]+$ ]]; then
      action="selection.image"
      args_json=$(jq -cn \
        --arg selectionId "$selection_id" \
        --argjson revision "$revision" \
        --arg lensToken "$lens_token" \
        '{selectionId: $selectionId, revision: $revision, lensToken: $lensToken}')
    elif [[ -n "$cell_id" && -z "$selection_id" && "$revision" =~ ^[0-9]+$ ]]; then
      action="output.capture.start"
      args_json=$(jq -cn \
        --arg cellId "$cell_id" \
        --argjson revision "$revision" \
        --arg lensToken "$lens_token" \
        '{cellId: $cellId, revision: $revision, lensToken: $lensToken}')
    else
      usage
    fi
    ;;
  activity | reveal)
    [[ ${#positionals[@]} -eq 0 && -n "$cell_id" && -n "$lens_token" ]] || usage
    [[ -z "$revision$selection_id" && "$summary_set" == false ]] || usage
    [[ "$command" == "activity" || "$label_set" == false ]] || usage
    message_json="null"
    [[ "$message_set" == false ]] ||
      message_json=$(jq -Rn --arg value "$message" '$value')
    label_json="null"
    [[ "$label_set" == false ]] ||
      label_json=$(jq -Rn --arg value "$label" '$value')
    action="$command"
    args_json=$(jq -cn \
      --arg cellId "$cell_id" \
      --arg lensToken "$lens_token" \
      --argjson label "$label_json" \
      --argjson message "$message_json" \
      '{
        cellId: $cellId,
        lensToken: $lensToken,
        label: $label,
        message: $message
      }')
    ;;
  resolve)
    [[ ${#positionals[@]} -ge 1 && "$revision" =~ ^[0-9]+$ ]] || usage
    [[ -n "$lens_token" && -z "$selection_id$cell_id" ]] || usage
    [[ "$message_set" == false && "$label_set" == false ]] || usage
    selection_ids_json=$(jq -cn '$ARGS.positional' --args "${positionals[@]}")
    summary_json="null"
    [[ "$summary_set" == false ]] ||
      summary_json=$(jq -Rn --arg value "$summary" '$value')
    action="resolve"
    args_json=$(jq -cn \
      --argjson selectionIds "$selection_ids_json" \
      --argjson revision "$revision" \
      --arg lensToken "$lens_token" \
      --argjson summary "$summary_json" \
      '{
        selectionIds: $selectionIds,
        revision: $revision,
        lensToken: $lensToken,
        summary: $summary
      }')
    ;;
  cleanup-images)
    [[ ${#target_args[@]} -eq 0 && ${#positionals[@]} -eq 1 ]] || usage
    [[ -z "$revision$lens_token$selection_id$cell_id" ]] || usage
    [[ "$message_set" == false && "$label_set" == false && "$summary_set" == false ]] ||
      usage
    image_dir="${positionals[0]}"
    ;;
  *)
    usage
    ;;
esac

invoke_action() {
  local requested_action="$1"
  local requested_args="$2"
  local marker config config_literal output line payload=""

  marker="__MARIMO_PAIR_LENS_${RANDOM}_${RANDOM}_$$_"
  config=$(jq -cn \
    --arg action "$requested_action" \
    --argjson args "$requested_args" \
    --arg marker "$marker" \
    '{action: $action, args: $args, marker: $marker}')
  config_literal=$(jq -Rn --arg value "$config" '$value')
  output=$(
    {
      printf '_MARIMO_LENS_CONFIG_JSON = %s\n' "$config_literal"
      cat "$python_script"
    } | bash "$execute_script" ${target_args[@]+"${target_args[@]}"}
  )

  while IFS= read -r line; do
    case "$line" in
      "$marker"*) payload="${line#"$marker"}" ;;
    esac
  done <<<"$output"

  if [[ -z "$payload" ]] || ! jq -e \
    --arg action "$requested_action" \
    '.action == $action and (.result | type == "object")' \
    >/dev/null <<<"$payload"; then
    echo "Lens returned an invalid response." >&2
    return 1
  fi
  printf '%s\n' "$payload"
}

status_exit() {
  local response="$1"
  case "$(jq -r '.result.status // empty' <<<"$response")" in
    absent | activity-requested | available | ready | removed | resolved | reveal-requested)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

emit_response() {
  local response="$1"
  local public_action="$2"
  jq -c --arg action "$public_action" '.action = $action' <<<"$response"
  status_exit "$response"
}

cleanup_image_dir() {
  local requested_dir="$1"
  local tmp_root canonical_dir
  tmp_root=$(cd "${TMPDIR:-/tmp}" && pwd -P)
  [[ -d "$requested_dir" && ! -L "$requested_dir" ]] || return 1
  canonical_dir=$(cd "$requested_dir" && pwd -P)
  [[ "$(dirname "$canonical_dir")" == "$tmp_root" ]] || return 1
  [[ "$(basename "$canonical_dir")" == marimo-pair-lens.* ]] || return 1
  [[ -f "$canonical_dir/.marimo-pair-lens-images" ]] || return 1
  rm -rf -- "$canonical_dir"
  jq -cn \
    --arg imageDir "$canonical_dir" \
    '{action: "cleanup-images", result: {status: "removed", imageDir: $imageDir}}'
}

materialize_image() {
  local response="$1"
  local status tmp_root image_dir image_path
  local expected_bytes actual_bytes expected_sha actual_sha
  status=$(jq -r '.result.status // empty' <<<"$response")
  [[ "$status" == "ready" || "$status" == "available" ]] || {
    emit_response "$response" "image"
    return
  }
  jq -e '
    .result.mediaType == "image/png"
    and (.result.data | type == "string")
    and (.result.bytes | type == "number")
    and (.result.sha256 | type == "string")
  ' >/dev/null <<<"$response" || {
    echo "Lens returned invalid image metadata." >&2
    return 1
  }

  tmp_root=$(cd "${TMPDIR:-/tmp}" && pwd -P)
  image_dir=$(mktemp -d "${tmp_root}/marimo-pair-lens.XXXXXX")
  chmod 700 "$image_dir"
  : >"$image_dir/.marimo-pair-lens-images"
  image_path="$image_dir/image.png"
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    jq -r '.result.data' <<<"$response" | base64 --decode >"$image_path"
  else
    jq -r '.result.data' <<<"$response" | base64 -D >"$image_path"
  fi
  chmod 600 "$image_path"

  expected_bytes=$(jq -r '.result.bytes' <<<"$response")
  actual_bytes=$(wc -c <"$image_path" | tr -d ' ')
  expected_sha=$(jq -r '.result.sha256' <<<"$response")
  if command -v sha256sum >/dev/null 2>&1; then
    actual_sha=$(sha256sum "$image_path" | awk '{print $1}')
  else
    actual_sha=$(shasum -a 256 "$image_path" | awk '{print $1}')
  fi
  if [[ "$actual_bytes" != "$expected_bytes" || "$actual_sha" != "$expected_sha" ]]; then
    rm -rf -- "$image_dir"
    echo "Decoded image does not match Lens metadata." >&2
    return 1
  fi

  jq -c \
    --arg path "$image_path" \
    --arg imageDir "$image_dir" \
    '
      .action = "image"
      | .result |= (
          del(.data)
          + {path: $path, imageDir: $imageDir, temporary: true}
        )
    ' <<<"$response"
}

if [[ "$command" == "cleanup-images" ]]; then
  cleanup_image_dir "$image_dir" || {
    echo "Refusing to remove an image directory not created by marimo-pair." >&2
    exit 1
  }
  exit
fi

if [[ "$command" != "image" ]]; then
  response=$(invoke_action "$action" "$args_json")
  emit_response "$response" "$command"
  exit
fi

response=$(invoke_action "$action" "$args_json")
if [[ "$action" == "selection.image" ]]; then
  materialize_image "$response"
  exit
fi

status=$(jq -r '.result.status // empty' <<<"$response")
if [[ "$status" != "pending" ]]; then
  emit_response "$response" "image"
  exit
fi
request_id=$(jq -r '.result.requestId // empty' <<<"$response")
[[ -n "$request_id" ]] || {
  echo "Lens did not return a capture request ID." >&2
  exit 1
}
read_args=$(jq -cn \
  --arg requestId "$request_id" \
  --arg lensToken "$lens_token" \
  '{requestId: $requestId, lensToken: $lensToken}')
deadline=$((SECONDS + 20))

while ((SECONDS < deadline)); do
  response=$(invoke_action "output.capture.read" "$read_args")
  status=$(jq -r '.result.status // empty' <<<"$response")
  case "$status" in
    pending)
      sleep 0.25
      ;;
    available)
      materialize_image "$response"
      exit
      ;;
    *)
      emit_response "$response" "image"
      exit
      ;;
  esac
done

jq -cn \
  --arg requestId "$request_id" \
  --arg cellId "$cell_id" \
  '{
    action: "image",
    result: {
      status: "capture-timeout",
      requestId: $requestId,
      cellId: $cellId
    }
  }'
exit 1
