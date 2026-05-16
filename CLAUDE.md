# Project Rules

- Work on current branch only unless told otherwise.
- Do not create temporary worktrees.
- Do not change unrelated files/pages.
- Keep changes small and focused.
- Match existing code style and patterns.
- UI should be clean, premium, modern, iOS-style.
- Use screenshots as reference when provided.
- Keep this file under 200 lines.
- If over 200 lines, summarize it.
- Run git status before/after changes.
- Run analyze/test after changes.

# Engineering Principles

## Think Before Coding

- State assumptions explicitly.
- Ask when requirements are unclear.
- Surface tradeoffs instead of silently choosing.
- Prefer simpler solutions when possible.

## Simplicity First

- Write minimum code needed.
- Avoid speculative abstractions/configuration.
- No unnecessary refactors.
- If implementation feels overcomplicated, simplify.

## Surgical Changes

- Touch only files related to the task.
- Do not refactor unrelated code.
- Remove only unused code introduced by your changes.
- Mention unrelated issues instead of fixing them automatically.

## Goal-Driven Execution

For non-trivial tasks:
1. Define success criteria.
2. Make focused changes.
3. Verify with tests/analyze/screenshots.
4. Confirm no unrelated diffs.

# Context Management

- Use /compact when context becomes large.
- Use /clear after completing each independent task/session.