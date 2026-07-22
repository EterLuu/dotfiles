alias ls='ls -G'

clipcopy() {
    pbcopy
}

clippaste() {
    pbpaste
}

clipopen() {
    open "${1:-.}"
}
