# Card W35-audit — which open backlog rows are already done, obsolete or still open

**Why:** `docs/BACKLOG.md` has ~150 rows not marked done; some were fixed by later waves without their row being updated
(B12 was fixed in wave 12). The lead plans the next waves from it, so it must be true.

**Read first:** `CLAUDE.md` (rules), `docs/BACKLOG.md`, `docs/PROGRESS.md`, `docs/DECISIONS.md` (search by id), `git log
--oneline` (search ids and keywords). Read code only as far as needed to decide one row.

**Task:** for every row whose status is not done/fixed/declined/rejected/wontfix, decide one of: **done** (cite the
commit or file:line that does it), **partly done** (what remains, one line), **obsolete** (superseded by a later
decision — cite it), **open** (still true; one line why, and a size guess S/M/L). Check by reading code and git
history, not by trusting the row. Do not edit any file: report only.

**Owned paths:** none (read-only). No builds, no sandboxes.

**Report:** a table `id | verdict | evidence / what remains | size`, sorted: done, obsolete, partly, open (open sorted
by user value: core mechanics and visible widget polish first). Then the top 15 open items you would schedule next, one
line each, and why.
