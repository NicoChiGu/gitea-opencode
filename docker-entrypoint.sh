#!/usr/bin/env sh
set -eu

if [ "$#" -eq 0 ]; then
  exec gitea-opencode
fi

case "$1" in
  sh|bash|/bin/sh|/bin/bash|node|npm|npx|git|tail|sleep|cat)
    exec "$@"
    ;;
  *)
    exec gitea-opencode "$@"
    ;;
esac
