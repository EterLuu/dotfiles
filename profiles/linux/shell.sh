alias ls='ls --color=auto'

clipcopy() {
    if command -v wl-copy >/dev/null 2>&1; then
        wl-copy
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard
    else
        printf 'install wl-clipboard or xclip\n' >&2
        return 127
    fi
}

clippaste() {
    if command -v wl-paste >/dev/null 2>&1; then
        wl-paste
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard -o
    else
        printf 'install wl-clipboard or xclip\n' >&2
        return 127
    fi
}

clipopen() {
    xdg-open "${1:-.}" >/dev/null 2>&1
}
