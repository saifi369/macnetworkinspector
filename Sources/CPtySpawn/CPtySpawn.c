#include "CPtySpawn.h"
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

pid_t cpty_spawn(const char *path, char *const argv[], int slave_fd) {
    pid_t pid = fork();
    if (pid != 0) {
        return pid; // parent (or fork failure: -1)
    }
    // Child: only async-signal-safe calls from here until exec.
    setsid();
    ioctl(slave_fd, TIOCSCTTY, 0);
    int devnull = open("/dev/null", O_RDONLY);
    if (devnull >= 0) {
        dup2(devnull, STDIN_FILENO);
    }
    dup2(slave_fd, STDOUT_FILENO);
    dup2(slave_fd, STDERR_FILENO);
    int max_fd = (int)sysconf(_SC_OPEN_MAX);
    for (int fd = 3; fd < max_fd; fd++) {
        close(fd);
    }
    execv(path, argv);
    _exit(127);
}
