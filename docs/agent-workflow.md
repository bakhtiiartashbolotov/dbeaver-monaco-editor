# Human–orchestrator–cloud-agent workflow

The project is complex enough that the quality of task boundaries matters more
than the length of an agent prompt. The cloud agent implements one accepted
unit. It does not own product scope or architecture.

## Roles

| Role | Owns |
| --- | --- |
| Product owner | UX priorities, support policy, risk acceptance, merge decision |
| Orchestrator/reviewer | Design consistency, plan decomposition, prompts, PR review, compatibility interpretation |
| Cloud implementation agent | One plan task, tests, commits, draft PR, evidence |
| CI | Reproducible automated evidence across targets and platforms |

The same person may be product owner and orchestrator. Keep the responsibilities
distinct even when one person performs both.

## Interaction rules that keep the agent effective

- Treat the issue plus numbered plan task as the contract for one run.
- Give repository/PR/check URLs and observed facts, not a retelling of the
  product discussion.
- Let the agent finish its stated checkpoint before sending another
  implementation request. A follow-up on the same branch should address that
  PR only.
- Ask for exact commands, output, changed paths, and residual risk. Do not
  accept “done” without inspectable evidence.
- When a blocker changes architecture, ask the agent for two options and a
  recommendation, then make the decision outside the implementation run.
- Never paste signing material, GitHub tokens, database credentials, or private
  SQL into prompts or issue comments.
- Merge only after a read-only review by someone other than the implementation
  agent. The orchestrator can fill that role; a separate fresh cloud reviewer
  is recommended for Tasks 1–3 and required for Tasks 4–10. Start the next
  task from updated `main`, not from the previous agent's working branch.

## Why not ask “build the whole plugin”

A broad prompt lets an agent make hidden decisions about:

- which model is canonical;
- how undo works;
- which DBeaver APIs are acceptable;
- whether a failed bridge may overwrite text;
- how much of DBeaver execution to reproduce;
- which platforms are actually tested.

Those choices are already made in the design and ADRs. A one-task prompt makes
the resulting diff reviewable and allows implementation evidence to influence
the next task without rewriting an entire branch.

## Standard cycle

```text
Accepted plan task
    -> issue
    -> fresh task branch/cloud session
    -> failing test or explicit scaffold gate
    -> minimal implementation
    -> focused and repository verification
    -> draft PR
    -> architecture/evidence review
    -> fixes in the same PR
    -> merge
    -> next issue
```

Never run independent implementation tasks against the same files in parallel.
Parallel agents are useful for read-only reviews or unrelated investigations.

## Context to give an implementation agent

Always provide:

- issue or pull-request URL;
- exact plan path and task number;
- exact relevant ADRs;
- the observed failure when debugging;
- files or subsystem allowed to change;
- acceptance gate and stop conditions.

Do not repeatedly paste:

- the full product conversation;
- every source link already in the design;
- speculative future features;
- unrelated PR diffs;
- credentials or database connection details.

The repository documents are durable context. The prompt identifies the
current slice.

## Prompt 1: first cloud run

Replace `[ISSUE_URL]` before sending:

```text
Work on [ISSUE_URL], “Task 1 — reproducible Tycho and npm scaffold”.

Read AGENTS.md, the complete approved design at
docs/superpowers/specs/2026-07-31-dbeaver-monaco-editor-design.md,
docs/architecture/README.md plus all accepted ADRs, and Task 1 only at
docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md.

Inspect git status and the existing tree. Before editing, report:
1. the exact task scope;
2. files expected to change;
3. the observed Linux/architecture and exact Task 1 toolchain preflight from
   `docs/cloud-development.md`;
4. any conflict or blocker.

Do not edit until that preflight passes. Treat an environment mismatch as a
blocker rather than installing an unpinned substitute.

Execute Task 1 only. Use the plan's exact versions and verification sequence.
Do not start Task 2 or add UI behavior. Use only the official DBeaver 26.1.0
product archive and its committed SHA-256; do not add a DBeaver update URL or
an independent Eclipse repository.

Commit at the plan checkpoints, run every Task 1 verification command, open a
draft PR with the repository template, and return the mandatory AGENTS.md
final report plus the repository URL, task branch, and draft PR URL. Stop with
evidence instead of inventing a workaround when p2 target preparation, Tycho
resolution, or the public API evidence differs.
```

## Prompt 2: next accepted task

Replace the bracketed values before sending:

```text
Implement Task [N: exact task title] from
docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md for Issue
[#number].

Base the work on current main after PR [#previous] merged. Read AGENTS.md, the
approved design, relevant ADRs [list], and Task [N] completely.

In this fresh checkout, run `bash scripts/bootstrap-workspace.sh` before the
first Maven command and report its observed result. Do not assume `.cache`
from another cloud session exists.

Execute only Task [N]. Preserve interfaces produced by earlier tasks. Start
with the specified failing test or explicit go/no-go probe. Do not broaden the
scope to Task [N+1].

Allowed files/subsystems:
- [exact paths from the task]

Stop and report evidence if:
- an approved interface cannot be implemented using public APIs;
- a new runtime dependency is needed;
- an invariant or ADR would have to change;
- the expected prerequisite from Task [N-1] is absent.

Run the exact focused and repository checks, update the same task branch,
open a draft PR, and return the AGENTS.md report.
```

## Prompt 3: read-only architecture review

Use a fresh agent that did not implement the PR:

```text
Review PR [URL] against:
- AGENTS.md;
- docs/superpowers/specs/2026-07-31-dbeaver-monaco-editor-design.md;
- relevant ADRs [list];
- Task [N] of
  docs/superpowers/plans/2026-07-31-bootstrap-and-vertical-spike.md.

This is read-only. Do not edit, commit, push, or approve.

Inspect the full diff and check evidence. Report findings ordered by severity
with exact file/line references. Focus on:
1. correctness and data-loss risk;
2. IDocument/undo/command ownership;
3. public versus internal DBeaver API usage;
4. cross-platform and fallback behavior;
5. disposal/concurrency;
6. bridge security and sensitive logging;
7. tests that can pass without proving the requirement.

Separate blocking findings, non-blocking improvements, and verified strengths.
If there are no blocking findings, say so explicitly and list residual risk.
```

## Prompt 4: address PR review

```text
Continue on PR [URL] and its existing branch. Read AGENTS.md, the original Task
[N], and all unresolved review comments.

For each comment:
1. verify the claim against code, tests, and the approved design;
2. classify it as valid, invalid, or requiring an architectural decision;
3. implement only valid in-scope fixes;
4. respond with evidence;
5. stop on architectural decisions instead of silently changing the design.

Run the focused checks for every changed subsystem and the Task [N] repository
checks. Push commits to the existing PR. Do not start the next plan task.
Return the mandatory AGENTS.md report and a comment-by-comment disposition.
```

## Prompt 5: debug a failing check

```text
Diagnose failure [workflow/check URL] on PR [URL]. Do not implement a fix until
you identify the root cause.

Read AGENTS.md and Task [N]. Inspect the failing job, exact command, full log,
and relevant recent diff. Reproduce the smallest failing command when
possible.

Return:
1. observed failure;
2. minimal reproduction;
3. root cause with evidence;
4. whether the fix is inside Task [N];
5. proposed minimal fix and regression test.

If the cause is a changed DBeaver/Eclipse API, target resolution, security
issue, or architecture conflict, stop for owner review. Otherwise implement
the approved in-scope fix, rerun focused and required checks, and update the
same PR.
```

## Prompt 6: compatibility-canary investigation

```text
Investigate the failing DBeaver compatibility canary [URL] read-only first.
Stable release checks are currently [status].

Compare the last passing and first failing DBeaver target. Inspect exported
bundle/package metadata and public API signatures used by
DBeaverEditorAdapter. Do not widen version ranges, add reflection, or suppress
the canary.

Report:
- first incompatible target;
- changed bundle/package/class/method;
- critical or optional capability affected;
- current safe fallback behavior;
- whether an existing adapter can handle it;
- options for a version-specific adapter and required tests.

Propose an ADR only if the public contract or support policy must change.
Do not modify stable code until the owner chooses an option.
```

## Stop conditions requiring a human decision

- Public DBeaver API differs from the approved contract.
- Checksum-pinned DBeaver product target cannot be reproduced.
- A runtime dependency or license boundary changes.
- Monaco would need to become the canonical model.
- Native save/execute cannot be used.
- Browser behavior is materially different across platforms.
- A security vulnerability lacks a tested safe resolution.
- A plan task needs unrelated refactoring to pass.
- A test can pass only by weakening an invariant.

The agent should report facts, two viable options when possible, a
recommendation, and the decision deadline. It must not turn a stop condition
into an implicit code choice.

## PR review checklist

### Scope

- Does the diff implement exactly one numbered task?
- Are unrelated formatting and dependency changes absent?
- Do file names and interfaces match the plan?

### Correctness

- Is `IDocument` still canonical?
- Is Eclipse undo still authoritative?
- Are epoch, revision, stamp, edit/selection sequence, recovery-export
  correlation, command replay, and UTF-16 semantics tested?
- Does resync require its exact committed handle/capture phase, and does replay
  cache the full command response under a single-use completion permit?
- Are external canonical events bounded by aggregate retained bytes as well as
  count?
- Can save/execute observe stale selection or text?

### Compatibility

- Are only public/exported APIs used?
- Is incompatible behavior detected before editing?
- Does optional failure stay optional?
- Does native DBeaver survive failure?

### Lifecycle and security

- Is every acquired listener/job/model/lease disposed?
- Does activation disposal preserve parent-owned breaker/unresolved recovery
  state and use a fresh lease on switch-back?
- Can Java and JavaScript block each other?
- Are commands allowlisted and payloads bounded?
- Are logs free of sensitive data?

### Evidence

- Was the focused test observed failing first where behavior changed?
- Are exact commands and results present?
- Does CI exercise what the PR claims?
- Are unsupported platforms/targets named rather than implied?

## Recommended cadence

- Use one cloud implementation session per task.
- Use an orchestrator/independent read-only review on every task.
- Use a separate fresh cloud reviewer for Tasks 4–10; it is recommended for
  Tasks 1–3.
- Review and merge before starting the next task.
- Run stable CI on every PR.
- Run newest/devel compatibility canary weekly.
- Revisit the plan after a go/no-go spike or incompatible API finding.

## Concise orchestrator status format

```markdown
## Current gate
Task/PR and acceptance state.

## Evidence
Passing and failing checks with links.

## Findings
Blocking first, then non-blocking.

## Decision needed
One concrete question with options and recommendation.

## Next agent prompt
The exact bounded prompt, sent only after the gate is accepted.
```
