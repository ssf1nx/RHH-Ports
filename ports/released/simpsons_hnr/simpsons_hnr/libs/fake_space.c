// Modern SD Cards, when large, will cause an integer overflow and make the game think the drive is full
// This shim tricks the game into reading a drive with 512MB free space, more than enough for save files
// Compile with gcc -fPIC -shared -o libfakespace.so fake_space.c -ldl on debian bullseye

#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/statvfs.h>
#include <sys/vfs.h>
#include <stddef.h>

int statvfs(const char *path, struct statvfs *buf) {
    int (*orig)(const char *, struct statvfs *) = dlsym(RTLD_NEXT, "statvfs");
    int ret = orig(path, buf);
    if (ret == 0) {
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bfree  = 500000;
        buf->f_frsize = 1024;
    }
    return ret;
}

int statvfs64(const char *path, struct statvfs64 *buf) {
    int (*orig)(const char *, struct statvfs64 *) = dlsym(RTLD_NEXT, "statvfs64");
    int ret = orig(path, buf);
    if (ret == 0) {
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bfree  = 500000;
        buf->f_frsize = 1024;
    }
    return ret;
}

int statfs(const char *path, struct statfs *buf) {
    int (*orig)(const char *, struct statfs *) = dlsym(RTLD_NEXT, "statfs");
    int ret = orig(path, buf);
    if (ret == 0) {
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bsize  = 1024;
    }
    return ret;
}

int statfs64(const char *path, struct statfs64 *buf) {
    int (*orig)(const char *, struct statfs64 *) = dlsym(RTLD_NEXT, "statfs64");
    int ret = orig(path, buf);
    if (ret == 0) {
        buf->f_blocks = 1000000;
        buf->f_bavail = 500000;
        buf->f_bsize  = 1024;
    }
    return ret;
}