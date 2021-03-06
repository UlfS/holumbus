#!/bin/bash

# ######################################
#
# ######################################

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROF_DIR="./prof"
PROG="hunt-membench"
FLAGS=""
FLAGS_PROF="-h -S -xt"
CABAL_BIN="$DIR/.cabal-sandbox/bin"
# extend to support more viewers
VIEWER=$(which okular evince | head -1)
CONFIG_FILE="prof.sh.config"


# use prof.sh.config to overwrite settings
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# ######################################

function repairHpFile() {
  local hp_file line_no hp_file_bak
  hp_file="$1"
  hp_file_bak="${hp_file}.bak"
  line_no=$(cat "$hp_file" | grep -n '^END_SAMPLE' | tail -n 1 | sed 's|\([0-9]*\).*|\1|')
  [ -z "$line_no" ] && echo ".hp file is too short" && return 1
  cp "$hp_file" "$hp_file_bak"
  head -n "$line_no" "$hp_file_bak" > "$hp_file"
}

function post() {
  repairHpFile "${PROG}.hp" && \
  hp2ps -c "${PROG}.hp"     && \
  ps2pdf "${PROG}.ps"
}

function move() {
  local data_dir="$PROF_DIR/$(date "+%y-%m-%d_%H-%M-%S")"
  if mkdir -p "$data_dir"
  then
    mv -t "$data_dir" "${PROG}.ps" "${PROG}.pdf" "${PROG}.summary" "${PROG}.hp" "${PROG}.hp.bak" "${PROG}.prof" "${PROG}.aux"
    echo "$data_dir"
  fi
}

function run() {
  time "$CABAL_BIN/$PROG" $@ $FLAGS +RTS -p $FLAGS_PROF -s${PROG}.summary -RTS
}

function view_dir() {
  local pdffile="$1/${PROG}.pdf"
  local sumfile="$1/${PROG}.summary"

  [ -e "$sumfile" ] && cat "$sumfile"

  if [ -n "$VIEWER" -a -e "$pdffile" ]
  then
    nohup "$VIEWER" "$pdffile" &>/dev/null &
  fi
}

# ######################################

ARGS="$@"

# ######################################
run $ARGS            && \
post                   && \
data_dir=$(move)       && \
view_dir "$data_dir"
