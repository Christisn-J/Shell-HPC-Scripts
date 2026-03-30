#!/bin/zsh
cd "$(cd "$(dirname "${(%):-%x}")/zshell" && pwd)" || exit 1
exec ./login.zsh "$@"
