# Invariants

Testable. Terms match the machine glossary in docs/reference.md.

1. Given bootstrap did not record an explicit yes, when the machine reaches
   first envelope, then no work-runtime unit is enabled.
2. Given a work agent requests a package, unit, or envelope patch, when it
   acts, then the action is an intent filed at the OS agent, not a live
   privileged write.
3. Given a skill in the catalog, when a work agent follows it, then the
   agent read the skill body in the current turn first.
4. Given a Connector for a service, when the work agent needs that service,
   then it uses the Connector and does not browser-around it.
5. Given a Worker finishes, when the human must see the outcome, then the
   speaking surface sends it. The Worker has no user voice.
6. Given a path on the operator computer, when a work-runtime tool is
   pointed at that path, then the path is not visible until approval, and
   copy is verbatim, not a mount.
7. Given system-scoped failure (unit failed, pacman abort, checker reject),
   when a toast is shown, then the wake belongs to the OS agent, not a work
   agent.
8. Given experimental enactment, when it is not yet checker-passed, then it
   lives in a worktree or subvolume under a cgroup — not as a live `/usr`
   mutation, and not as a snapper substitute.
9. Given notes, skills, routines, or connectors for this runtime, when they
   are stored, then they are git in `/srv/aios/src/work-runtime`, not in
   `/srv/aios/memory`.
10. Given disable, when user units stop, then the work-runtime git remains.
