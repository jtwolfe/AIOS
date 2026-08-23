# agent

Privileged proposer. systemd unit `aios-agent.service`, uid `aios-agent`
(L-02). Always *available*, idle by default (L-21). Does not merge to
`main` (HI-03).

On the machine the live tree is `/srv/aios/agent`. Bare git is
`/srv/aios/git/agent.git`, owned by `aios-checker`.

The unit is shipped for the installed system. It is not enabled on the
live ISO. firstboot copies it; it is not enabled during Harness A.
`ConditionPathExists=/etc/aios/envelope-accepted` (root-owned stamp, not
agent-writable JSON) keeps it from starting before accept even if enabled
by mistake. Envelope accept (P5) writes that stamp and starts the unit.

Provider adapters are `aios_agent/provider` (P4.2). Fixture is the
default; live is Grok device-code (L-17). The live OS token is
`/srv/aios/state/provider/os.token` (mode `0600`, uid `aios-agent`, not
in git). `aios-work` cannot read it (L-16, HI-13, HI-16). The checker
does not import this tree (HI-02). No turn loop (P4.3). No machine-goal
runner (P4.4). `enact syu` is the full `-Syu` window (P4.5). The unit
with no arguments still idles (L-21).

## Deny-list

`aios_agent/deny.py` refuses, even if a later loop asks:

- merge to `main` / force-push of published refs (HI-03)
- `curl | sh` and `/usr` mutation outside pacman (HI-04)
- partial `pacman -S` (L-04, HI-06)
- disable / mask / stop / restart / kill of the checker, snapper
  timers, etckeeper, or this unit (HI-06, L-12)

## Driver

```
python3 /srv/aios/agent/aios_agent/main.py
python3 /srv/aios/agent/aios_agent/main.py deny merge-main
python3 /srv/aios/agent/aios_agent/main.py deny unit disable aios-checker.service
python3 /srv/aios/agent/aios_agent/main.py provider path
python3 /srv/aios/agent/aios_agent/main.py provider fixture complete FILE [TEXT]
python3 /srv/aios/agent/aios_agent/main.py provider live login
```

With no arguments the service idles. It does not propose. It does not
parse intents or proposals (a malformed document must not exit the unit).
VM tests set `AIOS_PROVIDER=fixture` and `AIOS_FIXTURE`. Live login
prints a verification URL and user code on stderr; the token never
appears in the transcript. Run `provider live login` as `aios-agent`
(the unit). Do not `sudo` it; P7.6 TUI must not sudo this CLI. If
invoked as root, the adapter `chown`s the token to `aios-agent`.

## enact

The only sudo path is `/usr/lib/aios/bin/enact` (L-04). sudoers:

```
aios-agent ALL=(root) NOPASSWD: /usr/lib/aios/bin/enact
```

`aios-work` has no sudoers line. This uid is not in `wheel`.
