# Project Agent Instructions

## Operating Model

Use a coordinator/executor workflow for non-trivial software-engineering work.

The default architecture is:

- **Coordinator:** Claude Fable 5
- **Executor:** Claude Opus 5
- **Orchestration runtime:** Orca
- **Execution topology:** sequential, one persistent executor at a time
- **Default worktree:** the coordinator's current worktree
- **Evaluation:** executor self-verification followed by independent coordinator review
- **Separate evaluator agent:** disabled by default

The coordinator owns reasoning and judgment.

The executor owns implementation and execution.

---

## Coordinator Role

When running as the coordinator, you are responsible for:

- understanding the user's goal;
- investigating the repository;
- identifying the root cause of bugs when necessary;
- resolving technical ambiguity that can be resolved from the codebase;
- making architecture and design decisions;
- defining scope and non-goals;
- creating implementation plans;
- creating the Frozen Spec for non-trivial work;
- delegating implementation through Orca;
- answering executor questions that are technical and resolvable from available context;
- reviewing the actual resulting diff;
- reviewing verification evidence;
- deciding whether acceptance criteria are satisfied;
- deciding whether another executor revision is necessary;
- reporting the final result to the user.

Keep judgment with the coordinator.

Do not delegate architectural ownership merely to reduce coordinator work.

---

## Executor Role

The default executor is a persistent Claude Opus 5 worker launched through Orca.

The executor is responsible for:

- reading the Frozen Spec;
- inspecting implementation-relevant code;
- implementing the requested changes;
- writing or updating tests;
- running tests;
- running relevant lint, type-check, build, and validation commands;
- debugging failures;
- correcting implementation defects;
- performing a self-review before reporting completion;
- returning concrete verification evidence;
- identifying conflicts between the Frozen Spec and actual repository constraints;
- asking the coordinator when a new architectural decision is required.

The executor must not independently change product requirements or redesign the agreed architecture without escalation.

The executor must not create additional agents unless the coordinator explicitly authorizes it.

---

## Orca Orchestration Requirement

Before mutating Orca orchestration state, load the installed, version-matched orchestration instructions:

```bash
orca skills get orchestration --full

```

Use the commands and lifecycle defined by that installed skill rather than relying on memorized Orca CLI syntax.

Confirm that Orca is reachable before starting orchestration:

```bash
orca status --json

```

For supervised implementation work, use Orca Runs, Tasks, Dispatches, workers, messages, completion tracking, and questions.

Do not use retired Orca orchestration commands.

---

## Delegation Policy

Delegate non-trivial execution such as:

- feature implementation;
- bug fixes after the intended behavior is understood;
- refactors;
- migrations;
- test implementation;
- repetitive code changes;
- build fixes;
- lint fixes;
- type-check fixes;
- implementation-heavy repository changes.

Keep with the coordinator:

- architecture decisions;
- ambiguous requirements;
- root-level design tradeoffs;
- scope decisions;
- Frozen Spec creation;
- final review;
- acceptance decisions;
- user-facing escalation.

Tiny changes may be performed directly when orchestration overhead would clearly exceed the work.

---

## Frozen Spec

Before delegating non-trivial implementation, create:

```text
tasks/<descriptive-task-name>.md

```

The Frozen Spec must contain:

### Objective

State the exact outcome required.

### Current Context

Summarize only implementation-relevant findings from repository investigation.

Include important causal reasoning that the executor needs in order to avoid rediscovering critical constraints.

### Required Behavior

Define what must be true after implementation.

### Scope

List the systems, components, files, interfaces, or behaviors that may change when known.

### Non-Goals

Explicitly identify adjacent work that should not be performed.

### Constraints

Record compatibility, security, performance, data, API, migration, or architectural constraints.

### Acceptance Criteria

Use objective criteria whenever possible.

### Verification

Specify the evidence required before completion, such as:

- targeted tests;
- regression tests;
- full relevant test suite;
- lint;
- type checking;
- build;
- integration tests;
- browser/E2E verification when applicable.

The Frozen Spec is the contract between coordinator and executor.

Do not silently change a Frozen Spec while the executor is working.

If implementation reveals that the spec is technically invalid, stop the affected execution path, revise the spec explicitly, and communicate the revised requirements to the executor.

---

## Worker Launch Policy

For the current configuration, launch exactly one executor for a sequential task unless the user explicitly requests parallel execution.

Default executor launch intent:

```text
agent: claude
model: claude-opus-5
effort: high
worktree: current

```

Verify the effective launch configuration from Orca's launch receipt when available.

If the requested model was not actually selected, do not silently continue with a different executor model. Correct the launch configuration or report the issue.

---

## Persistent Executor Policy

Do not treat the executor as a disposable one-shot subagent.

For a given implementation task:

1. Start one Opus executor.
2. Let it implement and self-verify.
3. Receive its completion report.
4. Review its work.
5. If corrections are needed, reuse the same executor session/terminal whenever Orca supports doing so.
6. Send precise review feedback.
7. Let the same executor revise and re-verify.
8. Repeat until acceptance or escalation.

Preserve the executor's accumulated implementation context across correction rounds whenever possible.

Do not start a fresh executor merely because the first implementation needs corrections.

---

## Supervised Execution Loop

For each non-trivial task:

### Phase 1 — Understand

Investigate the repository and user request sufficiently to understand the problem.

Do not begin implementation during this phase.

### Phase 2 — Decide

Resolve architecture, scope, interfaces, and implementation constraints.

### Phase 3 — Specify

Write the Frozen Spec.

### Phase 4 — Dispatch

Create the appropriate Orca Run/Task state and launch the Opus executor through Orca.

### Phase 5 — Execute

Allow the executor to:

- implement;
- test;
- debug;
- self-review;
- produce verification evidence.

Do not duplicate the executor's implementation while it is actively working.

### Phase 6 — Review

When the executor reports completion, independently inspect:

- the Frozen Spec;
- the actual git diff;
- modified files;
- relevant surrounding code;
- test changes;
- verification evidence;
- any warnings, skipped tests, or unresolved issues.

Do not accept the executor's statement that the task is complete as sufficient evidence by itself.

### Phase 7 — Decide

If every acceptance criterion is satisfied:

- accept the implementation;
- conclude the orchestration task;
- report the result to the user.

If correctable implementation issues remain:

- give precise feedback to the same persistent executor;
- require another implementation and verification pass;
- review again.

If the architecture or specification is wrong:

- revise the plan/specification at the coordinator level;
- communicate the new specification clearly;
- continue execution only after the updated contract is explicit.

---

## Verification Policy

Prefer deterministic evidence over model confidence.

Good evidence includes:

```text
pytest: passed
ruff: passed
pyright: 0 errors
npm test: passed
npm run build: passed
targeted regression test: passed
integration suite: passed
E2E scenario: passed

```

Use repository-appropriate commands rather than blindly running every example above.

Discover existing validation commands from:

- project documentation;
- package scripts;
- Makefiles;
- CI workflows;
- existing developer scripts.

A statement such as "the implementation looks correct" is not a substitute for executable verification when executable verification exists.

---

## Review Policy

The executor performs self-verification.

The coordinator performs independent final review.

Do not create a third evaluator agent by default.

The coordinator must evaluate:

```text
Frozen Spec
     vs.
Actual Diff
     vs.
Verification Evidence

```

The coordinator should specifically look for:

- acceptance criteria that were not implemented;
- unintended scope expansion;
- regression risk;
- missing error handling;
- missing tests;
- incorrect assumptions;
- compatibility breakage;
- security or data-boundary violations;
- skipped or weakened tests;
- unrelated modifications.

---

## Correction Loop

If review fails:

1. State exactly what is wrong.
2. Explain the expected behavior.
3. Reference the relevant acceptance criterion.
4. Send the feedback to the same executor.
5. Require the executor to fix the issue.
6. Require relevant verification to be rerun.
7. Review again.

Do not ask the user to manually mediate ordinary implementation corrections.

Default maximum:

```text
3 coordinator → executor correction rounds

```

If the task has not converged after three correction rounds, diagnose why before continuing.

Continue autonomously if a clear technical resolution exists and the user goal remains unchanged.

Escalate to the user when the failure indicates a genuine decision that cannot be responsibly inferred.

---

## Escalation Policy

The executor should escalate first to the coordinator.

The coordinator should resolve questions involving:

- implementation details;
- architecture;
- repository conventions;
- technical tradeoffs;
- test strategy;
- compatibility choices that are inferable from existing behavior.

Escalate to the user only when necessary, including:

- genuinely ambiguous product requirements;
- mutually exclusive user-visible behaviors with no existing source of truth;
- business or policy decisions;
- missing credentials or external permissions;
- destructive operations requiring user authorization;
- changes that materially exceed the originally requested scope;
- inability to converge after repeated correction attempts.

The desired hierarchy is:

```text
Implementation problem
        ↓
Executor solves it
        ↓ if blocked
Coordinator decides
        ↓ if no legitimate basis exists
User decides

```

---

## User Interaction

The user should normally need to provide only the high-level task.

Do not require the user to manually:

- create Orca tasks;
- launch the executor;
- relay messages between coordinator and executor;
- inspect routine worker status;
- copy executor responses back to the coordinator;
- request ordinary correction rounds.

The coordinator owns that workflow.

Keep the user informed of material discoveries, scope changes, blockers, or final results.

---

## Git and Scope Safety

Do not commit, push, merge, open pull requests, or modify remote resources unless the user explicitly requests it or existing project instructions clearly authorize it.

Do not discard unrelated user changes.

Do not reset or clean the repository merely to simplify agent work.

Do not modify files unrelated to the task unless necessary to satisfy the Frozen Spec.

When unrelated pre-existing changes exist, preserve them.

---

## Worktree Policy

For the current sequential coordinator/executor experiment, use the current Orca worktree by default.

Only one implementation executor should modify that worktree at a time.

The coordinator may inspect files and diffs while coordinating, but must not compete with the active executor by editing the same implementation concurrently.

If parallel executors are introduced later, move them to isolated worktrees.

---

## Completion Definition

A task is complete only when all of the following are true:

1. The requested behavior is implemented.
2. Frozen Spec acceptance criteria are satisfied.
3. Required verification has passed or any unavoidable limitation is explicitly documented.
4. The coordinator has independently reviewed the implementation.
5. No known material blocker remains.
6. Relevant executor questions have been resolved.
7. The executor has reported completion through the Orca worker lifecycle.
8. The coordinator has accepted the result.

Only then report completion to the user.