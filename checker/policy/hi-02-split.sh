#!/bin/sh
# HI-02: shared judgement with the proposer is not a check.
set -eu

fail() {
  printf 'HI-02: %s\n' "$*" >&2
  exit 1
}

need_uid() {
  id -u "$1" >/dev/null 2>&1 || fail "sysuser $1 missing (L-02)"
}

need_uid aios-agent
need_uid aios-checker
need_uid aios-work
UA=$(id -u aios-agent)
UC=$(id -u aios-checker)
UW=$(id -u aios-work)
[ "${UA}" != "${UC}" ] && [ "${UA}" != "${UW}" ] && [ "${UC}" != "${UW}" ] \
  || fail "aios-agent/checker/work uids are not distinct (L-02)"

[ -f /etc/systemd/system/aios-checker.service ] \
  || fail "aios-checker.service missing"
grep -q '^User=aios-checker$' /etc/systemd/system/aios-checker.service \
  || fail "aios-checker.service is not User=aios-checker"
_st=$(systemctl is-enabled aios-checker.service 2>/dev/null || true)
[ "${_st}" = enabled ] || fail "aios-checker.service is ${_st:-missing}, not enabled"

if [ -f /etc/systemd/system/aios-agent.service ]; then
  grep -q '^User=aios-agent$' /etc/systemd/system/aios-agent.service \
    || fail "aios-agent.service is not User=aios-agent"
  grep -q '^User=aios-checker$' /etc/systemd/system/aios-agent.service \
    && fail "proposer unit shares the checker user"
fi

# Import guard: the checker tree must not name a model client module.
# The word this guard searches for is the aios_agent adapter package path.
TREE=/srv/aios/checker
[ -d "${TREE}" ] || fail "checker worktree missing"
_hit=$(grep -R -n -E --include='*.py' -- 'aios_agent\.|from aios_agent|import aios_agent' "${TREE}" 2>/dev/null | head -n 1 || true)
[ -z "${_hit}" ] || fail "checker imports a model client: ${_hit}"

SCHEMA=/srv/aios/checker/aios_checker/schema.py
[ -f "${SCHEMA}" ] || fail "schema.py missing"
grep -q 'HI-10' "${SCHEMA}" || fail "schema.py does not encode HI-10"

exit 0
