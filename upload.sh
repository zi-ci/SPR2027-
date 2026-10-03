#!/usr/bin/env bash

cd "$(dirname "$0")"

msg="${1:-自动提交，未输入备注}"
git add -A
git commit -m "$msg"
git pull --rebase
git push origin main
