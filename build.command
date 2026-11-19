#!/bin/bash
cd "$(dirname "$0")"
if ! command -v swift >/dev/null; then echo "Swift не найден. Выполните: xcode-select --install"; read -n1 -p "Нажмите любую клавишу…"; exit 1; fi
./build.sh 2>&1 | tee build.log
echo; echo "Код выхода: ${PIPESTATUS[0]} (лог: build.log)"
read -n1 -p "Нажмите любую клавишу…"
