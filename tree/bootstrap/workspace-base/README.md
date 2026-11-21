# @@BRAND@@ Workspace

This workspace is a persistent project area for AI-assisted development, research, analysis, and content creation.

## Standard directories

- `inputs/` — source files, references, datasets, and materials provided for the work
- `outputs/` — final or shareable deliverables produced by the project
- `tmp/` — temporary and reproducible working files
- `publish/` — static web pages to publish (created only when needed; the folder itself is public)
- `app/` — server app source (`app/<app-name>/` when there are several)
- `.private/` — credentials and personal data (mode 700, git-ignored)

## Basic rules

- Keep project-specific files inside this workspace.
- Store final deliverables in `outputs/` when practical.
- Use `tmp/` for disposable intermediate files.
- Do not store passwords, API keys, access tokens, private keys, or other credentials in the repository.
- Use only approved shared locations under `/shared`.
- Do not access another member's private workspace.
- Review changes and run appropriate tests or validation before committing code.
- Project-specific tools, frameworks, dependencies, and conventions may be added as needed.

## AI agents

This workspace may be used with Claude Code, Codex, Paseo, Antigravity, and other approved AI tools.

Agent-specific guidance is provided separately in:

- `CLAUDE.md`
- `AGENTS.md`

Project-specific instructions may extend these defaults.
