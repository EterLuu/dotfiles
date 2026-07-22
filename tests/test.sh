#!/usr/bin/env bash

set -eu

TEST_ROOT=$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run_dotfiles() {
    HOME=$TEST_HOME \
    XDG_CONFIG_HOME=$TEST_HOME/.config \
    XDG_STATE_HOME=$TEST_HOME/.local/state \
    "$TEST_ROOT/bin/dotfiles" "$@"
}

TEST_HOME=$TEST_TMP/link-home
mkdir -p "$TEST_HOME"
printf 'old vim config\n' > "$TEST_HOME/.vimrc"

run_dotfiles install --mode link >/dev/null
[ -L "$TEST_HOME/.vimrc" ] || fail '.vimrc was not linked'
[ -L "$TEST_HOME/.local/bin/dotfiles" ] || fail 'command was not linked'
run_dotfiles status --mode link >/dev/null || fail 'link status reported drift'
run_dotfiles doctor >/dev/null || fail 'doctor reported an unexpected failure'
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state \
    sh -c '. "$HOME/.profile"; [ "$DOTFILES_ROOT" = "$1" ]' sh "$TEST_ROOT" \
    || fail 'POSIX profile did not load the generated repository root'
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state \
    bash --noprofile --norc -c '. "$HOME/.bashrc"; [ "$DOTFILES_ROOT" = "$1" ]' bash "$TEST_ROOT" \
    || fail 'Bash configuration did not load the generated repository root'

FAKE_REPOSITORY=$TEST_TMP/stale-repository
mkdir -p "$FAKE_REPOSITORY"
cp "$TEST_ROOT/.dotfiles-manifest" "$FAKE_REPOSITORY/.dotfiles-manifest"
printf '%s\n' "$FAKE_REPOSITORY" > "$TEST_HOME/.config/dotfiles/root"
[ "$(run_dotfiles root)" = "$TEST_ROOT" ] || fail 'direct repository did not override a stale root hint'
run_dotfiles install --mode link >/dev/null

BACKED_UP=$(find "$TEST_HOME/.local/state/dotfiles/backups" -type f -name .vimrc -print | sed -n '1p')
[ -n "$BACKED_UP" ] || fail 'existing file was not backed up'
grep -q 'old vim config' "$BACKED_UP" || fail 'backup content changed'
[ -f "$TEST_HOME/.config/dotfiles/local.zsh" ] || fail 'local zsh file missing'
[ ! -L "$TEST_HOME/.config/dotfiles/local.zsh" ] || fail 'local zsh file must not be linked'

FAKE_CONDA=$TEST_TMP/"conda's path with spaces"
mkdir -p "$FAKE_CONDA/bin"
printf '#!/usr/bin/env sh\nexit 0\n' > "$FAKE_CONDA/bin/conda"
chmod +x "$FAKE_CONDA/bin/conda"
run_dotfiles config set conda-root "$FAKE_CONDA" >/dev/null
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config sh -c \
    '. "$XDG_CONFIG_HOME/dotfiles/generated.sh"; [ "$DOTFILES_CONDA_ROOT" = "$1" ]' sh "$FAKE_CONDA" \
    || fail 'Conda path with spaces was not quoted correctly'

run_dotfiles install --mode link >/dev/null
if run_dotfiles status --mode copy >/dev/null; then
    fail 'a symlink must not be accepted as a managed copy'
fi
run_dotfiles install --mode copy >/dev/null
[ ! -L "$TEST_HOME/.vimrc" ] || fail 'link-to-copy mode switch failed'
run_dotfiles install --mode link >/dev/null
[ -L "$TEST_HOME/.vimrc" ] || fail 'copy-to-link mode switch failed'
run_dotfiles uninstall --mode link >/dev/null
[ ! -e "$TEST_HOME/.vimrc" ] || fail 'managed link was not uninstalled'
[ -f "$TEST_HOME/.config/dotfiles/local.zsh" ] || fail 'uninstall removed local config'

TEST_HOME=$TEST_TMP/copy-home
mkdir -p "$TEST_HOME"
run_dotfiles install --mode copy >/dev/null
[ -f "$TEST_HOME/.bashrc" ] || fail '.bashrc was not copied'
[ ! -L "$TEST_HOME/.bashrc" ] || fail '.bashrc should be a regular copy'
run_dotfiles status --mode copy >/dev/null || fail 'copy status reported drift'
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state \
    "$TEST_HOME/.local/bin/dotfiles" status --mode copy >/dev/null \
    || fail 'copied command could not recover the repository root'
printf '\n# local accidental edit\n' >> "$TEST_HOME/.bashrc"
if run_dotfiles status --mode copy >/dev/null; then
    fail 'copy drift was not detected'
fi
run_dotfiles uninstall --mode copy >/dev/null 2>&1
[ -f "$TEST_HOME/.bashrc" ] || fail 'modified copied file should be kept on uninstall'
[ -f "$TEST_HOME/.config/dotfiles/local.bash" ] || fail 'copy uninstall removed local config'

printf 'All dotfiles integration tests passed.\n'
