# Interfaces

Surfaces, not live IDs. The OS agent synthesises against this list.

## User voice

The definition surface. Delivery is an explicit send.

| Surface | Purpose |
| --- | --- |
| send text | Visible reply or result. |
| attachments | Files on the definition surface. |
| question | Operator choice. Ends the turn; wait. |

Plain model text is not delivered.

## Work runtime

| Surface | Purpose |
| --- | --- |
| shell (workspace) | Command in the capped slice / worktree. |
| structured read | Line-numbered / paged read of workspace files. |
| memory | Operational notes for this job. Not a mind. |
| routine | Create / expire standing orders. Cron or listeners, never both. |
| skill follow | After reading the body this turn. |

Work processes run in `aios-work.slice` (`NoNewPrivileges`,
`ProtectSystem=strict`). They cannot see privileged trees.

## Operator computer

Approval-gated.

| Surface | Purpose |
| --- | --- |
| shell | Command after approval. |
| read | Structured read after approval. |
| copy to workspace | Verbatim transfer. |
| copy from workspace | Verbatim transfer. |

## OS agent

| Surface | Purpose |
| --- | --- |
| file intent | Write a structured intent to `/run/aios/intent.sock`. The OS agent is the only consumer. The work runtime does not enact privileged change. |

An intent is a record, not a shell: asked, clause if any, suggested oracles,
paths. The privileged proposer turns accepted intents into ordinary
proposals (branch, oracles, checker). A refused intent returns a structured
reason on the definition surface.

Calling `pacman` or `systemctl` from this tree is not an interface. The
kernel denies it (HI-13, HI-16).

## Web and MCP

| Surface | Purpose |
| --- | --- |
| search / fetch | Fallback when no Connector exists. |
| discover / call | Connector tools. Preferred. |

## Workers

| Surface | Purpose |
| --- | --- |
| dispatch | Start a Worker. No user voice. |
| check / stop | Inspect or halt. |
| coding on a branch | Repo work as a branch plus merge request. |
