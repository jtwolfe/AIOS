# Fleet

Routines that span more than one job without a human on every turn. Still
unprivileged.

## Trigger

Home-server work: maintaining VMs that run on the AIOS host, coordinating
backups across guests, restarting a failed guest *by filing an intent*.

## Do

- File VM lifecycle intents (define, start, stop, snapshot, destroy) at
  `/run/aios/intent.sock`. The OS agent proposes; the checker runs oracles;
  snapper covers host-side disk and unit changes.
- Keep guest work inside the guest. Host bridges, storage pools, and
  libvirt units are privileged.
- Cron *or* event listeners on one standing order, never both.
- Send results to the definition surface. Workers have no user voice.

## Don’t

- Don’t run `virsh`, `ip`, or `pacman` from the work slice and hope.
- Don’t treat a guest as a place to hide undeclared live state for the host.
- Don’t invent a second envelope that “the fleet lives in.”
