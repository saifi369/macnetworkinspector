#ifndef CPTYSPAWN_H
#define CPTYSPAWN_H
#include <sys/types.h>

/// Forks and execs `path` with `argv` as a new session leader whose controlling
/// terminal is the pty slave `slave_fd` (stdout/stderr go there, stdin is /dev/null).
/// Closing the pty master then delivers SIGHUP to the child, so it can never outlive us.
/// Returns the child pid, or -1 with errno set.
pid_t cpty_spawn(const char *path, char *const argv[], int slave_fd);

#endif
