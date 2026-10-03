#!/usr/bin/env bash

cd "$(dirname "$0")"

msg="${1:-自动提交}"
git add -A
git commit -m "$msg"
git push origin main
