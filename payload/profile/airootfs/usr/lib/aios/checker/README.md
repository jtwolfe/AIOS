# checker

Independent validator for privileged proposals. systemd unit
`aios-checker.service`, uid `aios-checker` (L-02). No model client
(HI-02, L-08).

A proposal is intent plus oracles. Empty oracle set → reject (HI-10).
Missing evidence → reject (HI-08). Only this uid fast-forwards or
squash-merges to `main` (HI-03, L-03).

On the machine the live tree is `/srv/aios/checker`. Bare git is
`/srv/aios/git/checker.git`, owned by `aios-checker`.

The unit is shipped for the installed system. It is not enabled on the
live ISO.

## Schema

`aios_checker/schema.py` loads `/srv/aios/state/proposals/<id>.json`.

```
{
  "id": "uuid-v4",
  "branch": "agent/<yyyy-mm-dd>-<slug>",
  "repos": ["state"],
  "intent": {
    "source": "human | envelope-clause | machine-goal | work-intent",
    "asked": "what was asked",
    "clause": "envelope/clauses/….md or null"
  },
  "oracles": ["policy/….sh", "pacman -Qi …"],
  "citations": ["https://wiki.archlinux.org/…"],
  "evidence": {"ran": ["policy/….sh"], "snapper_pre": 184}
}
```

## Merge gate

`aios_checker/merge.py`: `assert_merge_permitted` / `merge_to_main`.
Only uid `aios-checker` may fast-forward or squash-merge to `main`.
`merge` updates `refs/heads/main` on `/srv/aios/git/<name>.git`.

## Hooks

`hooks/{update,pre-receive,reference-transaction}` (plus `common.sh`) are
installed on every privileged bare repo at firstboot (L-03). They deny
`aios-agent` on `refs/heads/main`, deny force-push of published refs
(HI-03), and restrict the agent to `refs/heads/agent/*`. Only uid
`aios-checker` may fast-forward `main`.

## Driver

```
python3 /srv/aios/checker/aios_checker/main.py validate FILE.json
python3 /srv/aios/checker/aios_checker/main.py merge REPO BRANCH [--mode ff-only|squash]
```

With no arguments the service watches `proposals/` and schema-gates each
document. It does not re-run oracles or merge.

Exit 0 on pass, non-zero on fail. One-line reason on stderr.

## Policy

POSIX `sh` oracles in `policy/`. Same contract: exit 0 on pass, non-zero
on fail, one-line reason on stderr. The checker re-runs them without a
model client (HI-02, HI-08). One script per hard invariant (HI-01…17)
plus `packages-drift.sh`, `snapper-enabled.sh`, `etckeeper-enabled.sh`,
`boot-seatbelt.sh`, `no-partial-upgrade.sh`, `no-curl-sh.sh`,
`work-slice.sh`, `secrets-scan.sh`, and `pii-scan.sh`. They fail closed.
`true` is not an oracle.
