# Agent Instructions

This repository is a D codebase. Make changes in an idiomatic D style and keep them narrowly focused on the task at hand.

## General rules

- Prefer the standard library, especially Phobos, before adding third-party dependencies.
- Match the existing code style in nearby files and avoid unrelated formatting changes.
- Keep APIs small and explicit. Favor simple, readable code over clever abstractions.
- Preserve user changes and do not rewrite unrelated parts of the workspace.

## D-specific guidance

- Prefer value semantics, ranges, and Phobos algorithms where they fit naturally.
- Use `immutable`, `const`, and `scope` when they clarify intent and help correctness.
- Apply `@safe`, `nothrow`, `pure`, and `@nogc` only when they are a natural fit for the code; do not force them if they make the code harder to read.
- Use `unittest` blocks for behavior verification when adding or changing D modules.
- Keep module dependencies minimal and prefer small helper functions over large monolithic functions.
- Use DDoc tags for modules and any documentable element of the language

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

# Releases

- Changed shall be merged by MergeRequests und semi-linear history
- For the version we use the scheme YY.CW.FFFF with YY=Year-2000, CM is the calendary week and FF is a fraction
  0.9999 for the running week. (note: the D module va-toolbox should container some helper code to create this scheme from current
  time stamp.
- Any feature branch adds a comment about the change in simple non-technical english to the CHANGELOG.md
