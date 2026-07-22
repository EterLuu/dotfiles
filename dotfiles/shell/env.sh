# Shared, non-interactive-safe environment for Bash and Zsh.

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME

dotfiles_prepend_path() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH=$1${PATH:+:$PATH} ;;
    esac
}

dotfiles_prepend_path "$HOME/bin"
dotfiles_prepend_path "$HOME/.local/bin"
dotfiles_prepend_path "$HOME/.cargo/bin"
if [ -n "${DOTFILES_ROOT:-}" ]; then
    dotfiles_prepend_path "$DOTFILES_ROOT/bin"
fi
export PATH
unset -f dotfiles_prepend_path 2>/dev/null || unset dotfiles_prepend_path

if [ -z "${EDITOR:-}" ]; then
    if command -v nvim >/dev/null 2>&1; then
        EDITOR=nvim
    else
        EDITOR=vim
    fi
    export EDITOR
fi
: "${VISUAL:=$EDITOR}"
export VISUAL

: "${PAGER:=less}"
: "${LESS:=-FRX}"
export PAGER LESS

if [ -n "${DOTFILES_ROOT:-}" ] && [ -n "${DOTFILES_OS:-}" ]; then
    dotfiles_platform_env=$DOTFILES_ROOT/profiles/$DOTFILES_OS/env.sh
    if [ -r "$dotfiles_platform_env" ]; then
        # shellcheck disable=SC1090
        . "$dotfiles_platform_env"
    fi
    unset dotfiles_platform_env
fi
