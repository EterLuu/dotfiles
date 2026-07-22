# Shared interactive aliases and functions. Must remain valid in Bash and Zsh.

alias ..='cd ..'
alias ...='cd ../..'
alias ll='ls -alh'
alias la='ls -A'
alias c='clear'

mkcd() {
    [ "$#" -eq 1 ] || {
        printf 'usage: mkcd DIRECTORY\n' >&2
        return 2
    }
    mkdir -p "$1" && cd "$1"
}

croot() {
    if [ -n "${DOTFILES_ROOT:-}" ]; then
        cd "$DOTFILES_ROOT"
    else
        printf 'DOTFILES_ROOT is not set; run dotfiles install\n' >&2
        return 1
    fi
}

if [ -n "${DOTFILES_ROOT:-}" ] && [ -n "${DOTFILES_OS:-}" ]; then
    dotfiles_platform_shell=$DOTFILES_ROOT/profiles/$DOTFILES_OS/shell.sh
    if [ -r "$dotfiles_platform_shell" ]; then
        # shellcheck disable=SC1090
        . "$dotfiles_platform_shell"
    fi
    unset dotfiles_platform_shell
fi

if [ -n "${DOTFILES_ROOT:-}" ] && [ -n "${DOTFILES_HOST:-}" ]; then
    dotfiles_host_shell=$DOTFILES_ROOT/profiles/hosts/$DOTFILES_HOST/shell.sh
    if [ -r "$dotfiles_host_shell" ]; then
        # shellcheck disable=SC1090
        . "$dotfiles_host_shell"
    fi
    unset dotfiles_host_shell
fi
