#!/usr/bin/env bash

if [[ -t 0 ]]; then
  echo "Error: This script must be piped into, not run directly." >&2
  exit 1
fi

# default stops
R=(100 255 255 255)
G=(100 255 100 255)
B=(255 255 100 255)

TAB_WIDTH=4           # number of spaces that tabs expand to
WRAP_WIDTH=4294967296 # Hacky disable-by-default because i dont feel like implementing that properly right now

while getopts :ht:w: opt; do
  case $opt in
  h)
    echo "\
Applies line-by-line gradient coloring to, and wraps, text.
usage: command | $0 [options]
options:
  -h          show this text
  -t [theme]  change the color scheme
    themes:
      default, blueish, grays, rgb
  -w [width]  change the width to wrap to"
    exit 0
    ;;
  t)
    case $OPTARG in
    "default")
      ;;
    "blueish")
      R=(52 255 111 255 52 255)
      G=(111 255 52 255 180 255)
      B=(229 255 229 255 229 255)
      ;;
    "grays")
      R=(255 191 159 200)
      G=(255 191 159 200)
      B=(255 191 159 200)
      ;;
    "matrix")
      R=(100 255 120 255)
      G=(230 255 230 255)
      B=(100 255 120 255)
      ;;
    "rgb")
      R=(230 200 160)
      G=(160 230 200)
      B=(200 160 230)
      ;;
    *)
      echo "no theme \"$OPTARG\", using default." >&2
      ;;
    esac
    ;;
  w)
    if ! [[ $OPTARG =~ ^[1-9][0-9]*$ ]]; then
      echo "'$OPTARG' is not a valid width." >&2
      exit 1
    fi
    WRAP_WIDTH=$OPTARG
    ;;
  :)
    echo "Option -$OPTARG requires an argument." >&2
    exit 1
    ;;
  ?)
    echo "Invalid argument: -$OPTARG" >&2
    exit 1
    ;;
  esac
done

current_line=""
line_len=0
line_num=0

print_line_gradient() {
  local line="$1"
  local len=${#line}

  if ((len == 0)) || [[ "$line" =~ ^[[:space:]]*$ ]]; then
    printf "%s\n" "$line"
    return
  fi

  local num_stops=${#R[@]}

  local start_stop=$((line_num % num_stops))
  local end_stop=$(((line_num + 1) % num_stops))

  local vis_len=0
  local i
  for ((i = 0; i < len; i++)); do
    local char="${line:i:1}"
    if ! [[ "$char" =~ [[:space:]] ]]; then
      ((vis_len++))
    fi
  done

  if ((vis_len == 0)); then
    printf "%s\033[0m\n" "$line"
    return
  fi

  local denominator=$((vis_len - 1))
  if ((denominator < 1)); then
    denominator=1
  fi

  local vis_idx=0
  for ((i = 0; i < len; i++)); do
    local char="${line:i:1}"
    local is_space=0
    if [[ "$char" =~ [[:space:]] ]]; then
      is_space=1
    fi

    local r=$((R[start_stop] + (R[end_stop] - R[start_stop]) * vis_idx / denominator))
    local g=$((G[start_stop] + (G[end_stop] - G[start_stop]) * vis_idx / denominator))
    local b=$((B[start_stop] + (B[end_stop] - B[start_stop]) * vis_idx / denominator))

    printf "\033[38;2;%d;%d;%dm%s" "$r" "$g" "$b" "$char"

    if ((is_space == 0)); then
      ((vis_idx++))
    fi
  done

  printf "\033[0m\n"
  ((line_num++))
}

new_line() {
  print_line_gradient "$current_line"
  current_line=""
  line_len=0
}

append_to_line() {
  current_line+="$1"
  line_len=$((line_len + ${#1}))
}

emit_token() {
  local spaces="$1"
  local word="$2"

  if ((line_len > 0 && line_len + ${#spaces} + ${#word} > WRAP_WIDTH)); then
    new_line
    spaces=""
  fi

  while ((${#spaces} > 0)); do
    local avail=$((WRAP_WIDTH - line_len))
    if ((avail <= 0)); then
      new_line
      avail=$WRAP_WIDTH
    fi
    local chunk="${spaces:0:avail}"
    append_to_line "$chunk"
    spaces="${spaces:avail}"
  done

  local is_continuation=0
  while ((${#word} > 0)); do
    local avail=$((WRAP_WIDTH - line_len))
    if ((avail <= 0)); then
      new_line
      avail=$WRAP_WIDTH
    fi

    local prefix=""
    if ((is_continuation == 1 && WRAP_WIDTH >= 3)); then
      prefix="-"
      ((avail--))
    fi

    if ((${#word} <= avail)); then
      append_to_line "${prefix}${word}"
      word=""
    else
      if ((WRAP_WIDTH >= 3 && avail > 1)); then
        local take=$((avail - 1))
        local chunk="${word:0:take}"
        append_to_line "${prefix}${chunk}-"
        word="${word:take}"
        is_continuation=1
      else
        local chunk="${word:0:avail}"
        append_to_line "${prefix}${chunk}"
        word="${word:avail}"
      fi
    fi
  done
}

word_buf=""
space_buf=""
in_ansi=0
TAB_SPACES=$(printf "%${TAB_WIDTH}s" "")

while IFS= read -r -n1 char; do
  if ((in_ansi == 1)); then
    if [[ "$char" =~ [a-zA-Z] ]]; then
      in_ansi=0
    fi
    continue
  fi
  if [[ "$char" == $'\033' ]]; then
    in_ansi=1
    continue
  fi

  if [[ -z "$char" ]]; then
    if [[ -n "$word_buf" || -n "$space_buf" ]]; then
      emit_token "$space_buf" "$word_buf"
    fi
    new_line
    word_buf=""
    space_buf=""
    continue
  fi

  if [[ $char == $'\t' ]]; then
    char="$TAB_SPACES"
  fi

  if [[ "$char" =~ [[:space:]] ]]; then
    if [[ -n "$word_buf" ]]; then
      emit_token "$space_buf" "$word_buf"
      word_buf=""
      space_buf="$char"
    else
      space_buf+="$char"
    fi
  else
    word_buf+="$char"
  fi
done

if [[ -n "$word_buf" || -n "$space_buf" ]]; then
  emit_token "$space_buf" "$word_buf"
fi

if ((line_len > 0)); then
  new_line
fi

printf "\033[0m\n"
