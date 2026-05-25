# Project Rules

- Do NOT create worktrees or claude/* branches. Always work directly on the current branch.
- If unsure which branch to use, ask — do not create a new one.
- Do not create new branches or worktrees.
- Do not change unrelated files or pages.
- Keep changes small and focused — one task at a time.
- Match existing code style and patterns.
- UI: clean, premium, modern, iOS-style. Follow DESIGN.md.
- If a Figma or Claude design link is provided, follow it strictly.
- Use screenshots as reference when provided.
- Run `git status` before and after every change.
- Run `dart analyze` after every change. Fix all warnings before finishing.
- Keep this file under 200 lines. Summarize if over.

# Stack

- Flutter/Dart
- Firebase (auth, storage, database)
- Supabase (database (especially only images))
- Branches: `main` (production), `latest_develop` (active work)


# Context Management

- Use /compact when context becomes large.
- Use /clear after completing each independent task or session.
