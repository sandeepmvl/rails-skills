# Evals for `puma-tuning-and-concurrency`

## Prompt 1: "How many workers"
**User:** 4-CPU VM, Rails 8 monolith, I/O-bound. How many Puma workers + threads?
**Expected:** ~6 workers, 5 threads each. Memory budget check.
**Rubric:** [ ] Formula applied [ ] Memory check [ ] Did not propose 20+ threads

## Prompt 2: "Memory keeps growing"
**User:** Puma workers grow from 300MB to 1GB over a day.
**Expected:** Try jemalloc + MALLOC_ARENA_MAX=2 first. Then PumaWorkerKiller as workaround. Fix the leak ideally.
**Rubric:** [ ] jemalloc first [ ] PWK as workaround [ ] Root cause framing

## Prompt 3: "Threads = 25?"
**User:** I read more threads = more concurrency. Set threads = 25?
**Expected:** No — GIL contention. 5 is the sane default; scale workers, not threads.
**Rubric:** [ ] GIL explained [ ] Workers as scaling lever

## Prompt 4: "preload_app!"
**User:** What does preload_app! do?
**Expected:** Loads Rails once in master, forks workers via COW. Need on_worker_boot to reconnect DB.
**Rubric:** [ ] COW benefit [ ] DB reconnect required
