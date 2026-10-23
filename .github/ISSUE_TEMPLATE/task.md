---
name: Task
about: A scoped task for an AI or human worker
title: "FK-<id>: <short title>"
---

**Phase:** <0-6>
**Depends on:** <issue numbers, or none>

## Goal
One or two sentences: what exists after this task that didn't before.

## Context
The design or tech doc sections to read, and the files that already exist and matter.

## Do
- Concrete, checkable steps.

## Don't
- Things that are out of scope and must not be touched.

## Done when
- [ ] Acceptance criteria that can be checked (a test, a visible behaviour, `tools/check.sh` green).

## Report back (in the PR body)
Files changed, how it was tested, and open questions. Include `Closes #<this issue>`.
