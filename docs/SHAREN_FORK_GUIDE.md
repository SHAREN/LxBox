# SHAREN L×Box fork — documentation start

This fork follows upstream [Leadaxe/LxBox](https://github.com/Leadaxe/LxBox) (GPL-3.0). The purpose is to track and, when appropriate, implement general L×Box improvements with reproducible changes and clear documentation.

## Structure

- [Issues](https://github.com/SHAREN/LxBox/issues): proposed functionality, regression investigations, tests and maintenance.
- [Upstream repository](https://github.com/Leadaxe/LxBox): original source and updates.
- [Routing guide](https://github.com/Leadaxe/LxBox/blob/main/docs/USER_GUIDE.md): official user documentation.
- [Feature request — NORMAL/WHITELIST profiles](https://github.com/SHAREN/LxBox/issues/1): evaluate built-in workspaces and routing rules for explicit mobile-internet allowlists.

## Principles

1. Audit built-in L×Box features (Workspaces, Routing, Directions, Debug API and Automation) before implementing a duplicate.
2. Prioritize deterministic rule order, observable traffic paths, and rollbacks.
3. Keep credentials and customer-/device-specific runtime configurations out of this **public** fork.
4. Document each change with a descriptive commit message and a corresponding Issue or Pull Request.
5. If CI is introduced, use approved **self-hosted** runners only. Never introduce GitHub-hosted runners by default.

This Markdown document is a versioned public documentation entry. The GitHub Wiki feature is enabled, but its first wiki page must be initialized separately before a wiki Git remote can be used.
