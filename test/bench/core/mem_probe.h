/* Process memory probes, shared by bench_mem.c and bench_mem_vs.c.
 *
 * ONE INSTRUMENT, BOTH ENGINES. libghostty-vt exposes a custom-allocator
 * vtable, so its bytes could be counted exactly while ours came from a
 * process-wide statistic — and that asymmetry is a defect, not a bonus: two
 * different instruments disagreeing by a few percent is indistinguishable from
 * the engines differing by a few percent. Both sides are therefore measured
 * the same way, with libghostty on its default allocator (libc malloc, the
 * documented behaviour when NULL is passed) so both land in the same heap.
 *
 * Why two numbers rather than one. `mem_heap_in_use` counts what the allocator
 * has handed out; it is precise and machine-comparable, but blind to anything
 * a library maps outside malloc. `mem_footprint` counts resident pages and
 * sees everything, including mmap, but carries allocator slack and page
 * granularity. Reading them together is what catches a page-based engine whose
 * grid never passes through malloc at all — the two would diverge for one
 * engine and not the other, which is a finding, not noise.
 */
#ifndef MEM_PROBE_H
#define MEM_PROBE_H

#include <stddef.h>
#include <stdio.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#include <malloc/malloc.h>
#else
#include <malloc.h>
#include <unistd.h>
#endif

static size_t mem_heap_in_use(void) {
#if defined(__APPLE__)
    /* mstats() and not malloc_zone_statistics(malloc_default_zone(), ...):
       small allocations land in the nano zone, which the default zone's
       statistics do not count, so the per-zone call undercounts a grid of
       small row buffers by most of its size. mstats aggregates every zone. */
    struct mstats m = mstats();
    return (size_t)m.bytes_used;
#else
    struct mallinfo2 mi = mallinfo2();
    return (size_t)mi.uordblks;
#endif
}

static size_t mem_footprint(void) {
#if defined(__APPLE__)
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) !=
        KERN_SUCCESS)
        return 0;
    return (size_t)info.phys_footprint;
#else
    FILE *f = fopen("/proc/self/statm", "r");
    if (!f) return 0;
    long total = 0, rss = 0;
    if (fscanf(f, "%ld %ld", &total, &rss) != 2) rss = 0;
    fclose(f);
    return (size_t)rss * (size_t)sysconf(_SC_PAGESIZE);
#endif
}

#endif
