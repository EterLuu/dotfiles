#!/usr/bin/env bash

set -eu

TEST_ROOT=$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
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
printf 'legacy Bash history entry\n' > "$TEST_HOME/.bash_history"
mkdir -p "$TEST_HOME/.local/state/dotfiles/copy-base"
{
    printf '# previous deployed Bash version\n'
    cat "$TEST_ROOT/dotfiles/bash/bashrc"
} > "$TEST_HOME/.local/state/dotfiles/copy-base/.bashrc"
cp "$TEST_HOME/.local/state/dotfiles/copy-base/.bashrc" "$TEST_HOME/.bashrc"
printf '\n# installer addition from an old managed copy\n' >> "$TEST_HOME/.bashrc"
printf '# pre-existing local profile content\n' > "$TEST_HOME/.profile"
ln -s "$TEST_ROOT/dotfiles/zsh/zshrc" "$TEST_HOME/.zshrc"

run_dotfiles install --mode link >/dev/null
[ -L "$TEST_HOME/.vimrc" ] || fail '.vimrc was not linked'
[ -L "$TEST_HOME/.local/bin/dotfiles" ] || fail 'command was not linked'
[ -d "$TEST_HOME/.local/state/bash" ] || fail 'Bash history directory was not created'
[ -f "$TEST_HOME/.bashrc" ] && [ ! -L "$TEST_HOME/.bashrc" ] \
    || fail '.bashrc was not migrated to a local wrapper'
[ -f "$TEST_HOME/.zshrc" ] && [ ! -L "$TEST_HOME/.zshrc" ] \
    || fail '.zshrc managed link was not migrated to a local wrapper'
grep -q '^# dotfiles-local-wrapper:v1:bashrc$' "$TEST_HOME/.bashrc" \
    || fail '.bashrc wrapper marker is missing'
grep -q 'installer addition from an old managed copy' "$TEST_HOME/.bashrc" \
    || fail 'old installer addition was not preserved in the local wrapper'
if grep -q 'Portable interactive Bash configuration' "$TEST_HOME/.bashrc"; then
    fail 'old shared Bash source was duplicated inside the local wrapper'
fi
grep -q 'pre-existing local profile content' "$TEST_HOME/.profile" \
    || fail 'pre-existing profile content was not preserved'
run_dotfiles status --mode link >/dev/null || fail 'link status reported drift'
printf '\n# third-party installer addition stays local\n' >> "$TEST_HOME/.zshrc"
run_dotfiles status --mode link >/dev/null \
    || fail 'a local shell-wrapper edit was treated as managed drift'
if grep -q 'third-party installer addition stays local' "$TEST_ROOT/dotfiles/zsh/zshrc"; then
    fail 'a third-party shell addition leaked into the repository'
fi

DANGLING_REPO=$TEST_TMP/dangling-repository
DANGLING_HOME=$TEST_TMP/dangling-home
mkdir -p "$DANGLING_REPO/bin" "$DANGLING_HOME"
cp "$TEST_ROOT/bin/dotfiles" "$DANGLING_REPO/bin/dotfiles"
printf 'all|missing.conf|.missing.conf\n' > "$DANGLING_REPO/.dotfiles-manifest"
ln -s "$DANGLING_REPO/missing.conf" "$DANGLING_HOME/.missing.conf"
if HOME=$DANGLING_HOME DOTFILES_ROOT=$DANGLING_REPO \
    "$DANGLING_REPO/bin/dotfiles" status --mode link >/dev/null; then
    fail 'status accepted a managed link whose repository source is missing'
fi

run_dotfiles doctor >/dev/null || fail 'doctor reported an unexpected failure'
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state \
    sh -c '. "$HOME/.profile"; [ "$DOTFILES_ROOT" = "$1" ]' sh "$TEST_ROOT" \
    || fail 'POSIX profile did not load the generated repository root'
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state \
    bash --noprofile --norc -c '. "$HOME/.bashrc"; [ "$DOTFILES_ROOT" = "$1" ]' bash "$TEST_ROOT" \
    || fail 'Bash configuration did not load the generated repository root'
mkdir -p "$TEST_HOME/.config/nvm"
printf '%s\n' \
    'export DOTFILES_TEST_NVM_LOADED=1' \
    'nvm() { :; }' > "$TEST_HOME/.config/nvm/nvm.sh"
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state NVM_DIR= \
    bash --noprofile --rcfile "$TEST_HOME/.bashrc" -ic \
    'type nvm >/dev/null && [ "$DOTFILES_TEST_NVM_LOADED" = 1 ] &&
     history -s "persisted Bash history entry" && history -a' >/dev/null 2>&1 \
    || fail 'interactive Bash history or NVM setup failed'
grep -q 'legacy Bash history entry' "$TEST_HOME/.local/state/bash/history" \
    || fail 'legacy Bash history was not migrated'
grep -q 'persisted Bash history entry' "$TEST_HOME/.local/state/bash/history" \
    || fail 'Bash history was not persisted'
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state NVM_DIR= \
    bash --noprofile --rcfile "$TEST_HOME/.bashrc" -ic \
    'history | grep -q "persisted Bash history entry"' >/dev/null 2>&1 \
    || fail 'a new Bash shell did not reload the persisted history'
if rg -q '^[[:space:]]*IdentitiesOnly[[:space:]]+yes' "$TEST_ROOT/dotfiles/ssh/shared.conf"; then
    fail 'shared SSH defaults still force IdentitiesOnly yes'
fi

FAKE_REPOSITORY=$TEST_TMP/stale-repository
mkdir -p "$FAKE_REPOSITORY"
cp "$TEST_ROOT/.dotfiles-manifest" "$FAKE_REPOSITORY/.dotfiles-manifest"
printf '%s\n' "$FAKE_REPOSITORY" > "$TEST_HOME/.config/dotfiles/root"
[ "$(run_dotfiles root)" = "$TEST_ROOT" ] || fail 'direct repository did not override a stale root hint'
run_dotfiles install --mode link >/dev/null

BACKED_UP=$(find "$TEST_HOME/.local/state/dotfiles/backups" -type f -name .vimrc -print | sed -n '1p')
[ -n "$BACKED_UP" ] || fail 'existing file was not backed up'
grep -q 'old vim config' "$BACKED_UP" || fail 'backup content changed'
BACKED_UP_BASHRC=$(find "$TEST_HOME/.local/state/dotfiles/backups" -type f -name .bashrc -print | sed -n '1p')
[ -n "$BACKED_UP_BASHRC" ] || fail 'old Bash entry point was not backed up'
BACKED_UP_ZSHRC=$(find "$TEST_HOME/.local/state/dotfiles/backups" -type l -name .zshrc -print | sed -n '1p')
[ -n "$BACKED_UP_ZSHRC" ] || fail 'old Zsh managed link was not backed up'
BACKED_UP_ZSH_CONTENT=$(find "$TEST_HOME/.local/state/dotfiles/backups" -type f \
    -name '.zshrc.managed-content' -print | sed -n '1p')
[ -n "$BACKED_UP_ZSH_CONTENT" ] || fail 'linked Zsh content was not snapshotted'
cmp -s "$BACKED_UP_ZSH_CONTENT" "$TEST_ROOT/dotfiles/zsh/zshrc" \
    || fail 'linked Zsh content backup changed'
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
[ -f "$TEST_HOME/.bashrc" ] || fail '.bashrc local wrapper was not created'
[ ! -L "$TEST_HOME/.bashrc" ] || fail '.bashrc local wrapper must be a regular file'
sed '1s/v1/v0/' "$TEST_HOME/.bashrc" > "$TEST_HOME/.bashrc.old-wrapper"
mv "$TEST_HOME/.bashrc.old-wrapper" "$TEST_HOME/.bashrc"
printf '\n# third-party suffix on an older wrapper\n' >> "$TEST_HOME/.bashrc"
run_dotfiles install --mode copy >/dev/null
grep -q '^# dotfiles-local-wrapper:v1:bashrc$' "$TEST_HOME/.bashrc" \
    || fail 'an older local wrapper was not upgraded'
grep -q 'third-party suffix on an older wrapper' "$TEST_HOME/.bashrc" \
    || fail 'wrapper upgrade did not preserve the third-party suffix'
if grep -q '^# dotfiles-local-wrapper:v0:bashrc$' "$TEST_HOME/.bashrc"; then
    fail 'wrapper upgrade nested the old wrapper'
fi
run_dotfiles status --mode copy >/dev/null || fail 'copy status reported drift'
HOME=$TEST_HOME XDG_CONFIG_HOME=$TEST_HOME/.config XDG_STATE_HOME=$TEST_HOME/.local/state \
    "$TEST_HOME/.local/bin/dotfiles" status --mode copy >/dev/null \
    || fail 'copied command could not recover the repository root'
printf '\n# local accidental edit\n' >> "$TEST_HOME/.bashrc"
run_dotfiles status --mode copy >/dev/null \
    || fail 'local wrapper edit was incorrectly treated as copy drift'
run_dotfiles uninstall --mode copy >/dev/null 2>&1
[ -f "$TEST_HOME/.bashrc" ] || fail 'local wrapper should be kept on uninstall'
[ -f "$TEST_HOME/.config/dotfiles/local.bash" ] || fail 'copy uninstall removed local config'

# Exercise save/sync in an isolated repository with a local bare remote.
SAVE_REPO=$TEST_TMP/save-repository
SAVE_REMOTE=$TEST_TMP/save-remote.git
SAVE_HOME=$TEST_TMP/save-home
mkdir -p "$SAVE_REPO" "$SAVE_HOME"
cp -R "$TEST_ROOT/." "$SAVE_REPO/"
rm -rf "$SAVE_REPO/.git"
git -C "$SAVE_REPO" init -q
git -C "$SAVE_REPO" config user.name 'Dotfiles Test'
git -C "$SAVE_REPO" config user.email 'dotfiles-test@example.invalid'
git -C "$SAVE_REPO" config commit.gpgSign false
git -C "$SAVE_REPO" config core.autocrlf false
git -C "$SAVE_REPO" add -A
git -C "$SAVE_REPO" commit -q -m 'initial dotfiles'
git init -q --bare "$SAVE_REMOTE"
git -C "$SAVE_REPO" remote add origin "$SAVE_REMOTE"
SAVE_BRANCH=$(git -C "$SAVE_REPO" symbolic-ref --short HEAD)
git -C "$SAVE_REPO" push -q -u origin "$SAVE_BRANCH"

run_saved_dotfiles() {
    HOME=$SAVE_HOME \
    XDG_CONFIG_HOME=$SAVE_HOME/.config \
    XDG_STATE_HOME=$SAVE_HOME/.local/state \
    "$SAVE_REPO/bin/dotfiles" "$@"
}

run_saved_dotfiles install --mode copy >/dev/null
printf '\n# simulated conda init block remains device-local\n' >> "$SAVE_HOME/.zshrc"
run_saved_dotfiles save --mode copy -m 'must not capture local wrapper' >/dev/null
grep -q 'simulated conda init block remains device-local' "$SAVE_HOME/.zshrc" \
    || fail 'save removed a third-party local shell addition'
if grep -q 'simulated conda init block remains device-local' "$SAVE_REPO/dotfiles/zsh/zshrc"; then
    fail 'save captured a local shell wrapper into the repository'
fi
[ -z "$(git -C "$SAVE_REPO" status --porcelain)" ] \
    || fail 'local shell wrapper edit made the repository dirty'

# A config mutation writes device.conf before generated.sh. Force the second
# atomic rename to fail and verify that both files return to their old state.
CONFIG_GENERATED_SNAPSHOT=$TEST_TMP/generated-before-config-failure
CONFIG_FAIL_BIN=$TEST_TMP/config-fail-bin
CONFIG_FAIL_MARKER=$TEST_TMP/config-mv-failed
CONFIG_REAL_MV=$(command -v mv)
cp "$SAVE_HOME/.config/dotfiles/generated.sh" "$CONFIG_GENERATED_SNAPSHOT"
mkdir -p "$CONFIG_FAIL_BIN"
printf '%s\n' \
    '#!/usr/bin/env sh' \
    'for dotfiles_last_arg do :; done' \
    'if [ "$dotfiles_last_arg" = "$DOTFILES_TEST_FAIL_MV_TARGET" ] &&' \
    '   [ ! -e "$DOTFILES_TEST_FAIL_MV_MARKER" ]; then' \
    '    : > "$DOTFILES_TEST_FAIL_MV_MARKER"' \
    '    exit 1' \
    'fi' \
    'exec "$DOTFILES_TEST_REAL_MV" "$@"' > "$CONFIG_FAIL_BIN/mv"
chmod +x "$CONFIG_FAIL_BIN/mv"
if PATH=$CONFIG_FAIL_BIN:$PATH \
    DOTFILES_TEST_FAIL_MV_TARGET=$SAVE_HOME/.config/dotfiles/generated.sh \
    DOTFILES_TEST_FAIL_MV_MARKER=$CONFIG_FAIL_MARKER \
    DOTFILES_TEST_REAL_MV=$CONFIG_REAL_MV \
    run_saved_dotfiles config set conda-root "$SAVE_HOME/failing-conda" >/dev/null 2>&1; then
    fail 'config set unexpectedly succeeded after generated.sh rename failure'
fi
[ ! -e "$SAVE_HOME/.config/dotfiles/device.conf" ] \
    || fail 'failed config set did not remove the newly created device.conf'
cmp -s "$SAVE_HOME/.config/dotfiles/generated.sh" "$CONFIG_GENERATED_SNAPSHOT" \
    || fail 'failed config set did not restore generated.sh'
if find "$SAVE_HOME/.config/dotfiles" -name 'generated.sh.tmp.*' -print \
    | sed -n '1p' | grep -q .; then
    fail 'failed config set left a generated.sh temporary file'
fi

# A direct install is also atomic: a late missing source must roll back files
# already deployed earlier in the manifest.
INSTALL_MANIFEST_SNAPSHOT=$TEST_TMP/install-manifest-before-failure
INSTALL_WRAPPER_SNAPSHOT=$TEST_TMP/install-wrapper-before-failure
cp "$SAVE_REPO/.dotfiles-manifest" "$INSTALL_MANIFEST_SNAPSHOT"
cp "$SAVE_HOME/.zshrc" "$INSTALL_WRAPPER_SNAPSHOT"
printf 'pre-install local vim content\n' > "$SAVE_HOME/.vimrc"
rm "$SAVE_HOME/.inputrc"
printf 'all|dotfiles/missing-for-install.conf|.missing-for-install.conf\n' \
    >> "$SAVE_REPO/.dotfiles-manifest"
if run_saved_dotfiles install --mode copy >/dev/null 2>&1; then
    fail 'install unexpectedly succeeded with a missing manifest source'
fi
grep -q 'pre-install local vim content' "$SAVE_HOME/.vimrc" \
    || fail 'failed install did not restore a replaced HOME target'
[ ! -e "$SAVE_HOME/.inputrc" ] \
    || fail 'failed install did not restore a pre-install missing target'
cmp -s "$SAVE_HOME/.zshrc" "$INSTALL_WRAPPER_SNAPSHOT" \
    || fail 'failed install changed a local shell wrapper'
grep -q 'missing-for-install' "$SAVE_REPO/.dotfiles-manifest" \
    || fail 'failed install did not preserve the pre-install repository edit'
if find "$SAVE_HOME/.local/state/dotfiles/transactions" \
    \( -name ACTIVE -o -name IN_DOUBT \) -print 2>/dev/null | sed -n '1p' | grep -q .; then
    fail 'failed install left a recoverable transaction after successful rollback'
fi
if find "$SAVE_HOME/.local/state/dotfiles/backups" -maxdepth 1 \
    -type d -name 'transaction-*' -print 2>/dev/null | sed -n '1p' | grep -q .; then
    fail 'failed install left its transaction backup behind'
fi
cp "$INSTALL_MANIFEST_SNAPSHOT" "$SAVE_REPO/.dotfiles-manifest"
run_saved_dotfiles install --mode copy >/dev/null

# Refuse a transaction that could not restore an out-of-scope repository edit.
printf '\nlocal license edit outside transaction scope\n' >> "$SAVE_REPO/LICENSE"
if run_saved_dotfiles install --mode copy >/dev/null 2>&1; then
    fail 'install accepted an out-of-scope repository edit'
fi
grep -q 'local license edit outside transaction scope' "$SAVE_REPO/LICENSE" \
    || fail 'install preflight lost an out-of-scope repository edit'
git -C "$SAVE_REPO" restore -- LICENSE

TRANSACTION_LOCK=$SAVE_HOME/.local/state/dotfiles/transaction.lock
mkdir "$TRANSACTION_LOCK"
printf 'pid=%s\nrepository=%s\n' "$$" "$SAVE_REPO" > "$TRANSACTION_LOCK/owner"
if run_saved_dotfiles save --mode copy -m 'must respect lock' >/dev/null 2>&1; then
    fail 'save ignored another live transaction lock'
fi
rm -rf "$TRANSACTION_LOCK"

# A process killed after a durable checkpoint must leave an ACTIVE transaction.
# Recovery refuses post-crash edits, then rolls back once the exact checkpoint
# state has been restored.
ACTIVE_HEAD=$(git -C "$SAVE_REPO" rev-parse HEAD)
printf '\n# survives forced interruption in HOME\n' >> "$SAVE_HOME/.profile"
printf '\n# creates the forced-interruption commit\n' >> "$SAVE_HOME/.inputrc"
ACTIVE_HOME_CHECKPOINT=$TEST_TMP/active-home-checkpoint
cp -p "$SAVE_HOME/.profile" "$ACTIVE_HOME_CHECKPOINT"
printf '%s\n' \
    '#!/usr/bin/env sh' \
    'dotfiles_pid=$(ps -o ppid= -p "$PPID" | tr -d " ")' \
    '[ -n "$dotfiles_pid" ] || exit 2' \
    'kill -KILL "$dotfiles_pid"' \
    'exit 1' > "$SAVE_REPO/.git/hooks/pre-commit"
chmod +x "$SAVE_REPO/.git/hooks/pre-commit"
set +e
run_saved_dotfiles save --mode copy -m 'forced active interruption' >/dev/null 2>&1
ACTIVE_STATUS=$?
set -e
[ "$ACTIVE_STATUS" -ne 0 ] || fail 'forced interruption unexpectedly succeeded'
ACTIVE_MARKER=$(find "$SAVE_HOME/.local/state/dotfiles/transactions" -name ACTIVE -print | sed -n '1p')
[ -n "$ACTIVE_MARKER" ] || fail 'forced interruption did not retain an ACTIVE snapshot'
printf '# edit created after forced interruption\n' >> "$SAVE_HOME/.profile"
if run_saved_dotfiles recover >/dev/null 2>&1; then
    fail 'ACTIVE recovery overwrote state changed after the interruption'
fi
grep -q 'edit created after forced interruption' "$SAVE_HOME/.profile" \
    || fail 'failed ACTIVE recovery changed the post-interruption edit'
cp -p "$ACTIVE_HOME_CHECKPOINT" "$SAVE_HOME/.profile"
run_saved_dotfiles recover >/dev/null 2>&1
[ "$(git -C "$SAVE_REPO" rev-parse HEAD)" = "$ACTIVE_HEAD" ] \
    || fail 'ACTIVE recovery did not restore the original HEAD'
grep -q 'survives forced interruption in HOME' "$SAVE_HOME/.profile" \
    || fail 'ACTIVE recovery lost the original HOME edit'
[ -z "$(git -C "$SAVE_REPO" status --porcelain)" ] \
    || fail 'ACTIVE recovery left repository changes behind'
rm "$SAVE_REPO/.git/hooks/pre-commit"
run_saved_dotfiles sync --mode copy -m 'retry after active recovery' >/dev/null 2>&1

printf '\n" captured from HOME\n' >> "$SAVE_HOME/.vimrc"
run_saved_dotfiles sync --mode copy -m 'capture vim from home' >/dev/null 2>&1
grep -q 'captured from HOME' "$SAVE_REPO/dotfiles/vim/vimrc" \
    || fail 'sync did not capture a HOME copy'
[ "$(git --git-dir="$SAVE_REMOTE" log -1 --format=%s)" = 'capture vim from home' ] \
    || fail 'sync did not push the requested commit'
cmp -s "$SAVE_HOME/.vimrc" "$SAVE_REPO/dotfiles/vim/vimrc" \
    || fail 'sync did not reinstall the committed configuration'

# A push rejected after commit/rebase/deployment must restore every local layer.
ROLLBACK_HEAD=$(git -C "$SAVE_REPO" rev-parse HEAD)
ROLLBACK_REMOTE_HEAD=$(git --git-dir="$SAVE_REMOTE" rev-parse "$SAVE_BRANCH")
ROLLBACK_BASELINE=$TEST_TMP/vim-baseline-before-failed-push
cp "$SAVE_HOME/.local/state/dotfiles/copy-base/.vimrc" "$ROLLBACK_BASELINE"
printf '\n" must survive failed push in HOME\n' >> "$SAVE_HOME/.vimrc"
printf '#!/usr/bin/env sh\nexit 1\n' > "$SAVE_REPO/.git/hooks/pre-push"
chmod +x "$SAVE_REPO/.git/hooks/pre-push"
if run_saved_dotfiles sync --mode copy -m 'must roll back push failure' >/dev/null 2>&1; then
    fail 'sync unexpectedly succeeded with a rejecting pre-push hook'
fi
[ "$(git -C "$SAVE_REPO" rev-parse HEAD)" = "$ROLLBACK_HEAD" ] \
    || fail 'failed sync did not restore the original Git HEAD'
[ "$(git --git-dir="$SAVE_REMOTE" rev-parse "$SAVE_BRANCH")" = "$ROLLBACK_REMOTE_HEAD" ] \
    || fail 'failed sync changed the remote branch'
grep -q 'must survive failed push in HOME' "$SAVE_HOME/.vimrc" \
    || fail 'failed sync did not restore the edited HOME copy'
if grep -q 'must survive failed push in HOME' "$SAVE_REPO/dotfiles/vim/vimrc"; then
    fail 'failed sync left captured HOME content in the repository'
fi
cmp -s "$SAVE_HOME/.local/state/dotfiles/copy-base/.vimrc" "$ROLLBACK_BASELINE" \
    || fail 'failed sync did not restore the copy baseline'
[ -z "$(git -C "$SAVE_REPO" status --porcelain)" ] \
    || fail 'failed sync did not restore a clean repository worktree'
if find "$SAVE_HOME/.local/state/dotfiles/transactions" -mindepth 1 -print 2>/dev/null | sed -n '1p' | grep -q .; then
    fail 'successful rollback left a transaction snapshot behind'
fi
rm "$SAVE_REPO/.git/hooks/pre-push"

# The preserved HOME edit can be retried and committed normally.
run_saved_dotfiles sync --mode copy -m 'retry after atomic rollback' >/dev/null 2>&1
grep -q 'must survive failed push in HOME' "$SAVE_REPO/dotfiles/vim/vimrc" \
    || fail 'retry after rollback did not capture the preserved HOME edit'

# If push and verification both lose the remote, keep an in-doubt transaction
# until recover can determine whether commit or rollback is correct.
UNCERTAIN_HEAD=$(git -C "$SAVE_REPO" rev-parse HEAD)
printf '\n# must survive uncertain push in HOME\n' >> "$SAVE_HOME/.tmux.conf"
printf '%s\n' '#!/usr/bin/env sh' 'mv "$2" "${2}.offline"' 'exit 1' \
    > "$SAVE_REPO/.git/hooks/pre-push"
chmod +x "$SAVE_REPO/.git/hooks/pre-push"
set +e
run_saved_dotfiles sync --mode copy -m 'uncertain remote outcome' >/dev/null 2>&1
UNCERTAIN_STATUS=$?
set -e
[ "$UNCERTAIN_STATUS" -eq 2 ] || fail 'uncertain push did not return status 2'
[ "$(git -C "$SAVE_REPO" rev-parse HEAD)" != "$UNCERTAIN_HEAD" ] \
    || fail 'uncertain transaction did not retain its local commit'
UNCERTAIN_MARKER=$(find "$SAVE_HOME/.local/state/dotfiles/transactions" -name IN_DOUBT -print | sed -n '1p')
[ -n "$UNCERTAIN_MARKER" ] || fail 'uncertain push did not retain a recovery snapshot'
if run_saved_dotfiles save --mode copy -m 'must block unresolved transaction' >/dev/null 2>&1; then
    fail 'save started while an IN_DOUBT transaction existed'
fi
rm -rf "$TRANSACTION_LOCK"
if run_saved_dotfiles save --mode copy -m 'must still block unresolved transaction' >/dev/null 2>&1; then
    fail 'save ignored IN_DOUBT after its persistent lock was removed'
fi
if run_saved_dotfiles install --mode copy >/dev/null 2>&1; then
    fail 'install ran while an IN_DOUBT transaction existed'
fi
if run_saved_dotfiles config set install-mode copy >/dev/null 2>&1; then
    fail 'config mutation ran while an IN_DOUBT transaction existed'
fi
mv "$SAVE_REMOTE.offline" "$SAVE_REMOTE"
UNCERTAIN_HOME_CHECKPOINT=$TEST_TMP/uncertain-home-checkpoint
cp -p "$SAVE_HOME/.tmux.conf" "$UNCERTAIN_HOME_CHECKPOINT"
printf '# edit created after uncertain push\n' >> "$SAVE_HOME/.tmux.conf"
if run_saved_dotfiles recover >/dev/null 2>&1; then
    fail 'IN_DOUBT recovery overwrote state changed after the push attempt'
fi
grep -q 'edit created after uncertain push' "$SAVE_HOME/.tmux.conf" \
    || fail 'failed IN_DOUBT recovery changed the later HOME edit'
cp -p "$UNCERTAIN_HOME_CHECKPOINT" "$SAVE_HOME/.tmux.conf"
run_saved_dotfiles recover >/dev/null 2>&1
[ "$(git -C "$SAVE_REPO" rev-parse HEAD)" = "$UNCERTAIN_HEAD" ] \
    || fail 'recover did not roll back a transaction absent from the remote'
grep -q 'must survive uncertain push in HOME' "$SAVE_HOME/.tmux.conf" \
    || fail 'recover did not restore the HOME edit from an uncertain transaction'
if grep -q 'must survive uncertain push in HOME' "$SAVE_REPO/dotfiles/tmux/tmux.conf"; then
    fail 'recover left an uncommitted uncertain edit in the repository'
fi
rm "$SAVE_REPO/.git/hooks/pre-push"
run_saved_dotfiles sync --mode copy -m 'retry after uncertain recovery' >/dev/null 2>&1

# Also verify the other recovery decision: keep local state when the remote
# actually accepted the commit before connectivity was lost.
COMMITTED_BEFORE_HEAD=$(git -C "$SAVE_REPO" rev-parse HEAD)
printf '\n# remote contains uncertain transaction\n' >> "$SAVE_HOME/.tmux.conf"
printf '%s\n' \
    '#!/usr/bin/env sh' \
    'while read local_ref local_oid remote_ref remote_oid; do' \
    '    git --git-dir="$2" fetch "$PWD" "$local_oid" >/dev/null 2>&1 || exit 2' \
    '    git --git-dir="$2" update-ref "$remote_ref" "$local_oid" "$remote_oid" || exit 2' \
    'done' \
    'mv "$2" "${2}.offline"' \
    'exit 1' > "$SAVE_REPO/.git/hooks/pre-push"
chmod +x "$SAVE_REPO/.git/hooks/pre-push"
set +e
run_saved_dotfiles sync --mode copy -m 'remote accepted uncertain commit' >/dev/null 2>&1
COMMITTED_UNCERTAIN_STATUS=$?
set -e
[ "$COMMITTED_UNCERTAIN_STATUS" -eq 2 ] \
    || fail "accepted-but-unconfirmed push returned $COMMITTED_UNCERTAIN_STATUS instead of 2"
COMMITTED_UNCERTAIN_HEAD=$(git -C "$SAVE_REPO" rev-parse HEAD)
[ "$COMMITTED_UNCERTAIN_HEAD" != "$COMMITTED_BEFORE_HEAD" ] \
    || fail 'accepted uncertain transaction did not retain its local commit'
mv "$SAVE_REMOTE.offline" "$SAVE_REMOTE"
run_saved_dotfiles recover >/dev/null 2>&1
[ "$(git -C "$SAVE_REPO" rev-parse HEAD)" = "$COMMITTED_UNCERTAIN_HEAD" ] \
    || fail 'recover rolled back a commit that exists on the remote'
[ "$(git --git-dir="$SAVE_REMOTE" rev-parse "$SAVE_BRANCH")" = "$COMMITTED_UNCERTAIN_HEAD" ] \
    || fail 'accepted uncertain transaction is missing from the remote'
grep -q 'remote contains uncertain transaction' "$SAVE_REPO/dotfiles/tmux/tmux.conf" \
    || fail 'recover lost committed repository content'
rm "$SAVE_REPO/.git/hooks/pre-push"

# A rebase conflict must restore the pre-fetch local HEAD and HOME edit.
SAVE_OTHER=$TEST_TMP/save-other-clone
git clone -q "$SAVE_REMOTE" "$SAVE_OTHER"
git -C "$SAVE_OTHER" config user.name 'Dotfiles Other Test'
git -C "$SAVE_OTHER" config user.email 'dotfiles-other@example.invalid'
git -C "$SAVE_OTHER" config commit.gpgSign false
printf 'remote rebase version\n' > "$SAVE_OTHER/dotfiles/shell/inputrc"
git -C "$SAVE_OTHER" add dotfiles/shell/inputrc
git -C "$SAVE_OTHER" commit -q -m 'remote inputrc change'
git -C "$SAVE_OTHER" push -q
REBASE_ROLLBACK_HEAD=$(git -C "$SAVE_REPO" rev-parse HEAD)
REBASE_REMOTE_HEAD=$(git -C "$SAVE_OTHER" rev-parse HEAD)
REBASE_SOURCE_SNAPSHOT=$TEST_TMP/inputrc-before-rebase
REBASE_BASELINE_SNAPSHOT=$TEST_TMP/inputrc-baseline-before-rebase
cp "$SAVE_REPO/dotfiles/shell/inputrc" "$REBASE_SOURCE_SNAPSHOT"
cp "$SAVE_HOME/.local/state/dotfiles/copy-base/.inputrc" "$REBASE_BASELINE_SNAPSHOT"
printf 'home rebase version\n' > "$SAVE_HOME/.inputrc"
if run_saved_dotfiles sync --mode copy -m 'must roll back rebase conflict' >/dev/null 2>&1; then
    fail 'sync unexpectedly resolved a deliberate rebase conflict'
fi
[ "$(git -C "$SAVE_REPO" rev-parse HEAD)" = "$REBASE_ROLLBACK_HEAD" ] \
    || fail 'rebase rollback did not restore the original local HEAD'
[ "$(git --git-dir="$SAVE_REMOTE" rev-parse "$SAVE_BRANCH")" = "$REBASE_REMOTE_HEAD" ] \
    || fail 'rebase rollback changed or lost the remote commit'
cmp -s "$SAVE_REPO/dotfiles/shell/inputrc" "$REBASE_SOURCE_SNAPSHOT" \
    || fail 'rebase rollback did not restore the repository source'
grep -q 'home rebase version' "$SAVE_HOME/.inputrc" \
    || fail 'rebase rollback did not preserve the HOME-side edit'
cmp -s "$SAVE_HOME/.local/state/dotfiles/copy-base/.inputrc" "$REBASE_BASELINE_SNAPSHOT" \
    || fail 'rebase rollback did not restore the inputrc baseline'
[ -z "$(git -C "$SAVE_REPO" status --porcelain)" ] \
    || fail 'rebase rollback left repository changes behind'

# Reconcile the deliberate remote change before continuing other tests.
git -C "$SAVE_REPO" pull -q --ff-only
run_saved_dotfiles install --mode copy >/dev/null

printf '\nexport DOTFILES_TEST_REPOSITORY_UPDATE=1\n' >> "$SAVE_REPO/dotfiles/bash/bashrc"
run_saved_dotfiles save --mode copy -m 'repository-side update' >/dev/null
HOME=$SAVE_HOME XDG_CONFIG_HOME=$SAVE_HOME/.config XDG_STATE_HOME=$SAVE_HOME/.local/state NVM_DIR= \
    bash --noprofile --rcfile "$SAVE_HOME/.bashrc" -ic \
    '[ "$DOTFILES_TEST_REPOSITORY_UPDATE" = 1 ]' >/dev/null 2>&1 \
    || fail 'local wrapper did not load a repository-side Bash update'

printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' 'not-a-real-key' \
    > "$SAVE_REPO/dotfiles/ssh/leak.conf"
if run_saved_dotfiles save --mode copy -m 'must reject secret' >/dev/null 2>&1; then
    fail 'save did not reject staged private-key content'
fi
git -C "$SAVE_REPO" reset -q HEAD -- dotfiles/ssh/leak.conf
rm "$SAVE_REPO/dotfiles/ssh/leak.conf"

# update must deploy with the newly fetched manager, not the old functions
# already loaded by the parent process.
run_saved_dotfiles sync --mode copy -m 'prepare update rollback test' >/dev/null 2>&1
UPDATE_OTHER=$TEST_TMP/update-other-clone
git clone -q "$SAVE_REMOTE" "$UPDATE_OTHER"
git -C "$UPDATE_OTHER" config user.name 'Dotfiles Update Test'
git -C "$UPDATE_OTHER" config user.email 'dotfiles-update@example.invalid'
git -C "$UPDATE_OTHER" config commit.gpgSign false
sed 's/# Generated by dotfiles install. Do not edit./# Generated by self-updated dotfiles. Do not edit./' \
    "$UPDATE_OTHER/bin/dotfiles" > "$UPDATE_OTHER/bin/dotfiles.new"
mv "$UPDATE_OTHER/bin/dotfiles.new" "$UPDATE_OTHER/bin/dotfiles"
chmod +x "$UPDATE_OTHER/bin/dotfiles"
git -C "$UPDATE_OTHER" add bin/dotfiles
git -C "$UPDATE_OTHER" commit -q -m 'change updated manager deployment behavior'
git -C "$UPDATE_OTHER" push -q
run_saved_dotfiles update >/dev/null 2>&1
grep -q '^# Generated by self-updated dotfiles. Do not edit.$' \
    "$SAVE_HOME/.config/dotfiles/generated.sh" \
    || fail 'update deployed with the old in-memory manager'

# update must also roll back both the fast-forward and a partially applied
# install performed by that newly fetched manager.
printf 'all|dotfiles/missing-for-update.conf|.config/dotfiles/missing-for-update.conf\n' \
    >> "$UPDATE_OTHER/.dotfiles-manifest"
git -C "$UPDATE_OTHER" add .dotfiles-manifest
git -C "$UPDATE_OTHER" commit -q -m 'introduce failed update deployment'
git -C "$UPDATE_OTHER" push -q

UPDATE_HEAD=$(git -C "$SAVE_REPO" rev-parse HEAD)
UPDATE_HOME_SNAPSHOT=$TEST_TMP/bashrc-before-update
cp -p "$SAVE_HOME/.bashrc" "$UPDATE_HOME_SNAPSHOT"
chmod 755 "$SAVE_HOME/.ssh"
rmdir "$SAVE_HOME/.local/state/vim/backup" \
    "$SAVE_HOME/.local/state/vim/swap" \
    "$SAVE_HOME/.local/state/vim/undo" \
    "$SAVE_HOME/.local/state/vim"
if run_saved_dotfiles update >/dev/null 2>&1; then
    fail 'update unexpectedly succeeded with a missing manifest source'
fi
[ "$(git -C "$SAVE_REPO" rev-parse HEAD)" = "$UPDATE_HEAD" ] \
    || fail 'failed update did not restore the original HEAD'
cmp -s "$SAVE_HOME/.bashrc" "$UPDATE_HOME_SNAPSHOT" \
    || fail 'failed update did not restore HOME content'
[ "$(file_mode "$SAVE_HOME/.ssh")" = 755 ] \
    || fail 'failed update did not restore the original SSH directory mode'
[ ! -e "$SAVE_HOME/.local/state/vim" ] \
    || fail 'failed update left runtime directories that did not exist before it'
[ -z "$(git -C "$SAVE_REPO" status --porcelain)" ] \
    || fail 'failed update left repository changes behind'
if find "$SAVE_HOME/.local/state/dotfiles/transactions" \
    \( -name ACTIVE -o -name IN_DOUBT \) -print 2>/dev/null | sed -n '1p' | grep -q .; then
    fail 'failed update left a recoverable transaction after successful rollback'
fi

printf '\n# repository conflict side\n' >> "$SAVE_REPO/dotfiles/tmux/tmux.conf"
printf '\n# home conflict side\n' >> "$SAVE_HOME/.tmux.conf"
if run_saved_dotfiles save --mode copy -m 'must conflict' >/dev/null 2>&1; then
    fail 'save did not reject a two-sided copy conflict'
fi
grep -q 'repository conflict side' "$SAVE_REPO/dotfiles/tmux/tmux.conf" \
    || fail 'conflict rollback lost the original repository-side edit'
grep -q 'home conflict side' "$SAVE_HOME/.tmux.conf" \
    || fail 'conflict rollback lost the original HOME-side edit'
[ -z "$(git -C "$SAVE_REPO" diff --cached --name-only)" ] \
    || fail 'conflict rollback left staged changes behind'

printf 'All dotfiles integration tests passed.\n'
