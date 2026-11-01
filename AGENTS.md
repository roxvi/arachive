# Git workflow

After completing a task that changes this repository and passing relevant checks,
commit the changes you made and push the current branch to its configured upstream.
If no upstream is configured, ask which remote and branch to use.
Do not include unrelated user changes, force-push, or bypass failing checks.
If a push fails, report it; do not rewrite remote history.

## Distribution

- The canonical repository is `roxvi/arachive` (the requested repository spelling); the application remains **Archaive**. It combines the histories of `summrs` and `summrs-private`.
- Publish public release assets and use ordinary public download URLs in `roxvi/homebrew-tap`; installation must not require a GitHub token or a private repository.
- Use a Veil-style DMG: a large Finder window, clear drag-to-install instructions, large actual app/Applications icons, a connecting arrow, and minimal chrome.
- Keep the Archaive implementation and packaging standalone. Bump `VERSION` for installer updates; never replace published assets or checksums.
