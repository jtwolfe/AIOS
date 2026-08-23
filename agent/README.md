# agent

Privileged proposer. systemd unit `aios-agent.service`, uid `aios-agent`
(L-02). Always *available*, idle by default (L-21). Does not merge to
`main` (HI-03).

On the machine the live tree is `/srv/aios/agent`. Bare git is
`/srv/aios/git/agent.git`, owned by `aios-checker`.

The unit is shipped for the installed system. It is not enabled on the
live ISO. firstboot copies it; it is not enabled during Harness A.
Envelope accept (P5) starts it.

No provider or model client in this tree yet (P4.2). No turn loop (P4.3).
No machine-goal runner (P4.4). No `-Syu` window (P4.5).

## Deny-list

`aios_agent/deny.py` refuses, even if a later loop asks:

- merge to `main` / force-push of published refs (HI-03)
- `curl | sh` and `/usr` mutation outside pacman (HI-04)
- partial `pacman -S` (L-04, HI-06)
- disable / mask / stop of the checker, snapper timers, or this unit
  (HI-06, L-12)

## Driver

```
python3 /srv/aios/agent/aios_agent/main.py
python3 /srv/aios/agent/aios_agent/main.py deny merge-main
python3 /srv/aios/agent/aios_agent/main.py deny unit disable aios-checker.service
```

With no arguments the service idles. It does not propose. It does not
parse intents or proposals (a malformed document must not exit the unit).

## enact

The only sudo path is `/usr/lib/aios/bin/enact` (L-04). sudoers:

```
aios-agent ALL=(root) NOPASSWD: /usr/lib/aios/bin/enact
```

`aios-work` has no sudoers line. This uid is not in `wheel`.
