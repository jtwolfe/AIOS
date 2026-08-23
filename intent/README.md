# intent

Work → OS agent transport (L-05). Not a shell (HI-13). Not a proposal.

The socket unit is `aios-intent.socket` (`ListenStream=/run/aios/intent.sock`,
`SOCK_STREAM`, mode `0660`, owner `aios-agent`, group `aios-work`, `Accept=no`).
One JSON object per connection, then close. The privileged agent is the only
consumer. It ACKs a JSON result on the same connection. It does not execute
`asked` and does not `source` it.

Schema: [schema.json](schema.json). Checker validation is
`validate_work_intent` in `checker/aios_checker/schema.py` (same fields; not
the proposal document). The agent consumer is
`agent/aios_agent/intent_consume.py`.

`source` is `work-runtime` or `work-runtime-bots`. Proposal
`intent.source=work-intent` is a different document.
