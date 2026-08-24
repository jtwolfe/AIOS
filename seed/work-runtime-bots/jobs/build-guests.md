# Job: build-guests

path: /srv/aios/src/work-runtime-bots/jobs/build-guests.md
slice: aios-work.slice
skill: skills/fleet.md
state: idle

Standing order: keep build guests healthy. Host mutation
(define/start/stop/snapshot/destroy) is an intent at
`/run/aios/intent.sock`. Do not run `virsh` from the slice.
