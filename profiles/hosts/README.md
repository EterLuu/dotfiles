# Host-specific shared configuration

Create `profiles/hosts/<hostname>/shell.sh` only for non-secret settings that
should follow this host through Git. The installer exports the short hostname
as `DOTFILES_HOST` and loads that file after the common and platform settings.

Keep secrets and settings that must never be committed in
`~/.config/dotfiles/local.zsh`, `local.bash`, or `local.profile` instead.
