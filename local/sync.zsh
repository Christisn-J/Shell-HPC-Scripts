#!/bin/zsh
cd "$(dirname "$0")/zshell" || exit 1
exec ./sync.zsh "$@"
