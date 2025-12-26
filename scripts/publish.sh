#!/usr/bin/env bash
set -euo pipefail

msg="${1:-"actualización diaria"}"

git status
git add -A
git commit -m "$msg"
git push
