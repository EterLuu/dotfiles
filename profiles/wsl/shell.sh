alias ls='ls --color=auto'

clipcopy() {
    clip.exe
}

clippaste() {
    powershell.exe -NoProfile -Command Get-Clipboard 2>/dev/null | sed 's/\r$//'
}

clipopen() {
    explorer.exe "$(wslpath -w "${1:-.}")" >/dev/null 2>&1
}
