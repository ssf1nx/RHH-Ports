// This shim resolves a bug in https://github.com/ZenoArrows/The-Simpsons-Hit-and-Run/blob/master/libs/radcore/src/radfile/win32/win32drive.cpp#L605

// Modern SD Cards, when large, will cause an integer overflow and make the game think the drive is full
// This shim tricks the game into reading a drive with 512MB free space, more than enough for save files
// Compile with gcc -fPIC -shared -o libfakespace.so fake_space.c -ldl on debian bullseye

#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/statvfs.h>
#include <sys/vfs.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

static int fakespace_hits = 0;

__attribute__((constructor))
static void fakespace_init(void)
{
    fprintf(stderr, "[fakespace] libfakespace loaded\n");
}

__attribute__((destructor))
static void fakespace_fini(void)
{
    if (fakespace_hits == 0)
        fprintf(stderr,
            "[fakespace] WARNING: shim loaded but never used\n");
    else
        fprintf(stderr,
            "[fakespace] shim used (%d interceptions)\n",
            fakespace_hits);
}

int statvfs(const char *path, struct statvfs *buf)
{
    static int (*orig)(const char *, struct statvfs *) = NULL;
    if (!orig)
        orig = dlsym(RTLD_NEXT, "statvfs");

    int ret = orig(path, buf);
    if (ret == 0)
    {
        fakespace_hits++;
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bfree  = 500000;
        buf->f_frsize = 1024;
    }
    return ret;
}

int statvfs64(const char *path, struct statvfs64 *buf)
{
    static int (*orig)(const char *, struct statvfs64 *) = NULL;
    if (!orig)
        orig = dlsym(RTLD_NEXT, "statvfs64");

    int ret = orig(path, buf);
    if (ret == 0)
    {
        fakespace_hits++;
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bfree  = 500000;
        buf->f_frsize = 1024;
    }
    return ret;
}

int statfs(const char *path, struct statfs *buf)
{
    static int (*orig)(const char *, struct statfs *) = NULL;
    if (!orig)
        orig = dlsym(RTLD_NEXT, "statfs");

    int ret = orig(path, buf);
    if (ret == 0)
    {
        fakespace_hits++;
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bfree  = 500000;
        buf->f_bsize  = 1024;
    }
    return ret;
}

int statfs64(const char *path, struct statfs64 *buf)
{
    static int (*orig)(const char *, struct statfs64 *) = NULL;
    if (!orig)
        orig = dlsym(RTLD_NEXT, "statfs64");

    int ret = orig(path, buf);
    if (ret == 0)
    {
        fakespace_hits++;
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bfree  = 500000;
        buf->f_bsize  = 1024;
    }
    return ret;
}

long syscall(long number, ...)
{
    static long (*orig_syscall)(long, ...) = NULL;
    if (!orig_syscall)
        orig_syscall = dlsym(RTLD_NEXT, "syscall");

    va_list ap;
    va_start(ap, number);

    if (number == __NR_statfs || number == __NR_fstatfs)
    {
        const char *path = va_arg(ap, const char *);
        struct statfs *buf = va_arg(ap, struct statfs *);

        long ret = orig_syscall(number, path, buf);
        if (ret == 0 && buf)
        {
            fakespace_hits++;
            buf->f_blocks = 1000000;
            buf->f_bavail = 500000;
            buf->f_bfree  = 500000;
            buf->f_bsize  = 1024;
        }
        va_end(ap);
        return ret;
    }

    long a1 = va_arg(ap, long);
    long a2 = va_arg(ap, long);
    long a3 = va_arg(ap, long);
    long a4 = va_arg(ap, long);
    long a5 = va_arg(ap, long);
    long a6 = va_arg(ap, long);
    va_end(ap);

    return orig_syscall(number, a1, a2, a3, a4, a5, a6);
}
