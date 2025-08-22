---
argument-hint: 'Natural language task, e.g., "Add payments skeleton with Android & iOS screens, network stubs and secure store."'
description: 'Natural-language KMP pipeline: interpret intent → normalize args → orchestrate coders → build.'
allowed-tools: Bash(git status:*), Bash(git branch --show-current:*), Bash(ls:-la *), Bash(uname:-a)
---

## Context snapshot
- Git status: !`git status`
- Branch: !`git branch --show-current`
- Repo root: !`ls -la`

## Task
You are **@kmp-nl-router**.

**User instruction (freeform):**  
`$ARGUMENTS`

**Do the following:**
1) Inspect the workspace (see Context) and infer:
   - iOS integration (spm|pods),
   - existing modules (db/network/security/interop),
   - missing scaffold pieces.
2) Parse the instruction using the router heuristics to produce a **normalized argument line**:  
   `feature=<slug> mode=Skeleton|Impl modules=<csv> lanes=android,ios ios_integration=spm|pods notes="<summary>"`
3) If essential details are ambiguous, ask **at most 3 short questions** (yes/no or single-choice). If unanswered, use safe defaults.
4) Save a brief plan to `orchestration/plan-nlp.md` (raw text is fine).
5) **Action:** @kmp-orchestrator should execute with the normalized arguments, then hand off to @kmp-build-engineer for Debug/Simulator builds. Place artifacts under `artifacts/**` and logs under `build-logs/**`.

## Output
- Echo the normalized arguments you derived.
- Summarize the plan and any assumptions.
- Note any blockers (e.g., signing, private repos).