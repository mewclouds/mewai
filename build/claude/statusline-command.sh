#!/usr/bin/env bash
# Claude Code status line: model, reasoning effort, context window, git branch + dir, rate limits.
input=$(cat)

# Extract a top-level or nested JSON string/number value without jq.
json_get() {
    printf '%s' "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}[^\",}]*\"\{0,1\}" | head -1 | sed -E "s/\"$1\"[[:space:]]*:[[:space:]]*//; s/^\"//; s/\"$//"
}

model=$(json_get display_name)
[ -z "$model" ] && model="unknown"
effort=$(json_get level)
cwd=$(json_get current_dir)
[ -z "$cwd" ] && cwd=$(json_get cwd)
used_pct=$(json_get used_percentage)
five_hour=$(printf '%s' "$input" | grep -o '"five_hour"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')
seven_day=$(printf '%s' "$input" | grep -o '"seven_day"[^}]*"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$')

RESET="\033[0m"
CYAN="\033[36m"
YELLOW="\033[33m"
GREEN="\033[32m"
MAGENTA="\033[35m"

model_segment="${CYAN}${model}${RESET}"
[ -n "$effort" ] && model_segment="${model_segment} ${YELLOW}(${effort})${RESET}"

dir_name=$(basename "$cwd" 2>/dev/null)
branch=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
fi
if [ -n "$branch" ]; then
    location_segment="${GREEN}${branch}${RESET}:${dir_name}"
else
    location_segment="${dir_name}"
fi

context_segment=""
if [ -n "$used_pct" ]; then
    context_segment=$(printf "Ctx:%.0f%%" "$used_pct")
fi

limits_segment=""
if [ -n "$five_hour" ]; then
    limits_segment="5h:$(printf '%.0f' "$five_hour")%"
fi
if [ -n "$seven_day" ]; then
    [ -n "$limits_segment" ] && limits_segment="$limits_segment "
    limits_segment="${limits_segment}7d:$(printf '%.0f' "$seven_day")%"
fi

parts=("$model_segment" "$location_segment")
[ -n "$context_segment" ] && parts+=("${MAGENTA}${context_segment}${RESET}")
[ -n "$limits_segment" ] && parts+=("$limits_segment")

output=""
for part in "${parts[@]}"; do
    if [ -z "$output" ]; then
        output="$part"
    else
        output="$output | $part"
    fi
done

printf "%b\n" "$output"
