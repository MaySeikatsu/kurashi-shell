/* netjoin.c: LD_PRELOAD helper of tools/bench/sandbox.sh (I58).
 * A process started with the sandbox's env lines joins the sandbox's user and network namespaces before main() runs,
 * so it has loopback only. The env names the namespace: KURASHI_SANDBOX_NETNS_PID is its holder (netns-hold.py, the
 * sandbox's sway) and KURASHI_SANDBOX_NETNS_ID the namespace id the holder recorded ("net:[inode]"). Fail closed: when
 * the holder is gone, or its namespace is not the recorded one (a reused pid), the process stops with status 111
 * instead of running on the host network. Joining needs no privilege: the holder's user namespace is owned by our uid.
 * A process that already sits in a network namespace with loopback only runs as it is (row 94, B26): Chromium's
 * sandboxed zygote and renderers start in an empty namespace of their own and cannot open the holder's.
 *   cc -shared -fPIC -O2 -Wall -Werror -o netjoin.so netjoin.c
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void refuse(const char *what) {
    dprintf(2, "netjoin: %s: %s; not started (the sandbox has no host network)\n", what, strerror(errno));
    _exit(111);
}

static int same_ns(const struct stat *a, const struct stat *b) {
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}

/* True when this process's network namespace has no interface but loopback (/proc/self/net/dev follows the caller's
 * namespace). Unreadable counts as not isolated. */
static int loopback_only(void) {
    char line[256];
    int n = 0, others = 0;
    FILE *f = fopen("/proc/self/net/dev", "re");
    if (!f) return 0;
    while (fgets(line, sizeof line, f)) {
        char *colon = strchr(line, ':'), *name = line;
        if (++n <= 2 || !colon) continue; /* two header lines */
        *colon = 0;
        while (*name == ' ') name++;
        if (strcmp(name, "lo") != 0) others++;
    }
    fclose(f);
    return n > 2 && others == 0;
}

__attribute__((constructor))
static void join_sandbox_netns(void) {
    const char *pid = getenv("KURASHI_SANDBOX_NETNS_PID");
    const char *id = getenv("KURASHI_SANDBOX_NETNS_ID");
    char path[64];
    unsigned long want;
    struct stat cur, tgt_net, tgt_user;
    int nfd, ufd;

    if (!pid || !id) return;
    if (loopback_only()) return; /* no network to leave: the sandbox's own namespace, or one inside it */
    if (sscanf(id, "net:[%lu]", &want) != 1) {
        errno = EINVAL;
        refuse("KURASHI_SANDBOX_NETNS_ID is not net:[inode]");
    }
    snprintf(path, sizeof path, "/proc/%s/ns/net", pid);
    if ((nfd = open(path, O_RDONLY | O_CLOEXEC)) < 0) refuse(path);
    snprintf(path, sizeof path, "/proc/%s/ns/user", pid);
    if ((ufd = open(path, O_RDONLY | O_CLOEXEC)) < 0) refuse(path);
    if (fstat(nfd, &tgt_net) != 0) refuse("stat the sandbox network namespace");
    if ((unsigned long)tgt_net.st_ino != want) {
        errno = ESRCH;
        refuse("the holder's network namespace is not the one the sandbox recorded");
    }
    if (stat("/proc/self/ns/net", &cur) == 0 && same_ns(&cur, &tgt_net)) return; /* already in it */
    if (fstat(ufd, &tgt_user) != 0) refuse("stat the sandbox user namespace");
    if (stat("/proc/self/ns/user", &cur) != 0 || !same_ns(&cur, &tgt_user)) {
        if (setns(ufd, CLONE_NEWUSER) != 0) refuse("join the sandbox user namespace");
    }
    if (setns(nfd, CLONE_NEWNET) != 0) refuse("join the sandbox network namespace");
    close(ufd);
    close(nfd);
}
