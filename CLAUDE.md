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

## Animation & UI Interaction Standards
- Every user action must have a response animation or UI interaction.
- Button press: scale down slightly (0.96) with a bounce-back on release.
- Success actions (save, update, delete): show a clear success indicator —
  checkmark animation, snackbar, or modal — consistent with existing patterns.
- Screen transitions: use smooth slide or fade, never hard cuts.
- Tab/toggle switches: animate the pill/thumb and fade in/out any
  fields that appear or disappear (duration ~250ms, ease curve).
- Icon state changes (e.g. toggles): use AnimatedSwitcher or
  TweenAnimationBuilder — smooth color + scale transition, never abrupt.
- List changes (add, delete, reorder): animate the item in/out,
  never snap. Use AnimatedList or implicit animations.
- Loading states: always show a skeleton or spinner, never a blank screen.
- Empty states: always show a meaningful empty state UI, never blank.
- All animations: duration 200–350ms, use ease or easeInOut curves.
  Never use linear for UI animations.
- When in doubt: add the animation. Smooth > static, always.

# Stack

- Flutter/Dart
- Firebase (auth, storage, database)
- Supabase (database (especially only images))
- Branches: `main` (production), `latest_develop` (active work)


# Context Management

- Use /compact when context becomes large.
- Use /clear after completing each independent task or session.
