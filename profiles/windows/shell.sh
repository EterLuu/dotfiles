alias ls='ls --color=auto'

clipcopy() {
    clip.exe
}

clippaste() {
    powershell.exe -NoProfile -Command Get-Clipboard 2>/dev/null | sed 's/\r$//'
}

clipopen() {
    if command -v cygpath >/dev/null 2>&1; then
        explorer.exe "$(cygpath -w "${1:-.}")" >/dev/null 2>&1
    else
        explorer.exe "${1:-.}" >/dev/null 2>&1
    fi
}
