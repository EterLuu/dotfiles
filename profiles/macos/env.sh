# Homebrew uses different prefixes on Apple Silicon and Intel Macs.
for dotfiles_brew_bin in /usr/local/bin /opt/homebrew/bin; do
    if [ -d "$dotfiles_brew_bin" ]; then
        case ":$PATH:" in
            *":$dotfiles_brew_bin:"*) ;;
            *) PATH=$dotfiles_brew_bin:$PATH ;;
        esac
    fi
done
unset dotfiles_brew_bin
export PATH
