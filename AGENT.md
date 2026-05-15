# Agent Instructions

This repository is a D codebase. Make changes in an idiomatic D style and keep them narrowly focused on the task at hand.

## General rules

- Prefer the standard library, especially Phobos, before adding third-party dependencies.
- Match the existing code style in nearby files and avoid unrelated formatting changes.
- Keep APIs small and explicit. Favor simple, readable code over clever abstractions.
- Preserve user changes and do not rewrite unrelated parts of the workspace.
- Use English for all comments and documentation.

## D-specific guidance

- Prefer value semantics, ranges, and Phobos algorithms where they fit naturally.
- Use `immutable`, `const`, and `scope` when they clarify intent and improve correctness.
- Apply `@safe`, `nothrow`, `pure`, and `@nogc` only when they are a natural fit for the code; do not force them if they make the code harder to read.
- Use `unittest` blocks for behavior verification when adding or changing D modules.
- When using Silly, name every `unittest` with a string UDA such as `@("descriptive test name")` so the runner can report and filter it cleanly.
- Keep module dependencies minimal and prefer small helper functions over large monolithic functions.
- Use DDoc tags for modules and other documentable language elements.
- For structs and classes, an end-of-line DDoc comment is preferred for structure or class member variable when the description is short; use `/** ... */` just before the structure/class member when the documentation becomes long or multi-line.
- For every documented function, method, or helper, include a `Params:` section for arguments and a `Returns:` section for the result, even when the return value is `void`.
- Document private types, methods, functions, and other meaningful helpers with DDoc when they are part of the implementation contract or maintenance surface.

## Resource management

- For SDL2 or Vulkan resources, prefer explicit ownership and deterministic cleanup.
- Wrap handles in small types when that makes lifetime management clearer.
- Ensure allocation, initialization, and destruction paths stay balanced and easy to audit.

## Validation

- If this project has DUB metadata, validate with the smallest relevant command, usually `dub test` for behavior changes or `dub build` for compile-only checks.
- If there are targeted tests for the touched module, run those first.
- If no project metadata exists yet, note that clearly and use the nearest available compile or static check.

## Workflow

- Inspect nearby code before editing and prefer the smallest change that solves the problem.
- Add or update tests when behavior changes.
- If a change affects public APIs or build steps, update the documentation alongside the code.

## SDL findings

- Check the installed `bindbc-sdl` binding before using SDL names from online examples; this workspace has SDL3-style naming in a few places.
- Treat `SDL_KeyboardEvent.repeat` as important for one-shot shortcuts like object switching.
- For plus/minus shortcuts, support both `equals` / `minus` and keypad `kpPlus` / `kpMinus` scancodes.
- Keep overlay math and screen-space conversion explicit; Y should be flipped exactly once when converting from window pixels to NDC.
- Keep SDL/Vulkan resource ownership balanced and deterministic, especially for mapped buffers and window-surface cleanup.

## Commit workflow

- Keep each commit focused on one coherent change.
- Stage only the files that belong to that change.
- Write commit subjects in technical English and add a body when the change needs context.
- Merge feature branches with an explicit merge commit (`--no-ff`); do not fast-forward feature branch merges into long-lived branches.
- For release commits, update `CHANGELOG.md`, generate the release timetag with `scripts/release_timetag.d`, and tag the commit with a leading `v`.
- Do not commit generated build artifacts such as compiled helper binaries.

## Patchstack and commits

- Organize larger changes as a clean patchstack where each commit covers one coherent technical change.
- Keep related edits together in the same commit instead of splitting a single behavioral change across multiple commits.
- Write commit summaries and descriptions in technical English.
- Explain both what changed and why it was necessary.
- When a commit contains more than a trivial change, add a fuller body that gives the relevant technical context, tradeoffs, and any implementation notes needed for review.
- Prefer a linear sequence of self-contained commits that can be reviewed and reverted independently.

# Release guidelines

- Changes should be merged through merge requests and semi-linear history.
- For versioning, use the scheme YY.CW.FFFF, where YY is the year minus 2000, CW is the calendar week, and FF is a fraction.
- The FF value should be 0.9999 for the current week.
- The D module va-toolbox should contain helper code to generate this scheme from the current timestamp.
- Any feature branch should add a simple, non-technical English note about the change to CHANGELOG.md.
- Tag versions in GitLab with a leading v character.
