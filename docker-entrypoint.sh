#!/bin/bash
set -e

## Color Bash Prompt
# Read more at https://wiki.archlinux.org/index.php/Color_Bash_Prompt
PS1='\[\e[0;32m\]\u\[\e[m\] \[\e[1;34m\]\w\[\e[m\] \[\e[1;32m\]\$\[\e[m\] \[\e[1;37m\]'

exec "$@"
