# Claude Code Project Guidelines

## Scope

Work within the current project workspace unless the user explicitly requests otherwise.

Do not access another member's private workspace.

Use shared resources only through approved locations under `/shared`.

## Workspace conventions

- Use `./inputs` for source materials, references, and datasets when appropriate.
- Use `./outputs` for final or shareable deliverables when appropriate.
- Use `./tmp` for temporary or reproducible intermediate files.
- Use `./publish` only for static web pages that should be published. A folder named `publish` is public once the server sees it — ask the user first.
- Keep server app source under `./app` (or `./app/<app-name>`), and credentials or personal data under `./.private` (mode 700, git-ignored). Never put them in the home directory, in `./publish`, or under `/shared`.
- Preserve the existing project structure and conventions when they already exist.

## Security

Do not store or expose credentials such as:

- passwords
- API keys
- access tokens
- private keys
- session secrets
- authentication cookies

Do not place credentials in source files, logs, outputs, or version control.

## Changes

Before making significant changes:

- inspect the relevant files
- understand the existing project structure
- avoid unrelated modifications

After making changes:

- review the diff when Git is available
- run relevant tests, checks, builds, or validation when practical
- clearly report failures or unresolved issues

Do not delete or overwrite user files unless the task clearly requires it.

## Dependencies and tooling

Do not assume a specific framework or technology stack.

When a project already contains manifests, lockfiles, configuration, or established tooling, use those conventions first.

Avoid unnecessary global installations or system-level changes.

## Shared filesystem

The shared filesystem is mounted at `/shared`.

Approved collaboration areas include:

- `/shared/documents`
- `/shared/datasets`
- `/shared/workspaces`

Do not treat `/shared` itself as a general writable workspace.

## Claude Code behavior

- Prefer inspecting existing files before editing.
- Keep changes focused on the user's request.
- Use the project's existing commands and tooling when available.
- Ask for approval when Claude Code requires permission for sensitive or broader actions.
- Do not bypass project or environment safety controls.

## Project-specific instructions

Project-specific instructions may extend or override these defaults when explicitly defined within the project.
