// This shim resolves a bug in https://github.com/ZenoArrows/The-Simpsons-Hit-and-Run/blob/master/libs/radcore/src/radfile/win32/win32drive.cpp#L605

// Modern SD Cards, when large, will cause an integer overflow and make the game think the drive is full
// This shim tricks the game into reading a drive with 512MB free space, more than enough for save files
// Autosaves will still give an error, but manual saving works
// Compile with gcc -fPIC -shared -o libfakespace.so fake_space.c -ldl on debian bullseye

#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/statvfs.h>
#include <sys/vfs.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

static void apply_fake_stats(void *buf, int is_vfs) {
    if (is_vfs) {
        struct statvfs *v = (struct statvfs *)buf;
        v->f_bsize = v->f_frsize = 1024;
        v->f_blocks = 32768; 
        v->f_bfree = v->f_bavail = 16384;
    } else {
        struct statfs *s = (struct statfs *)buf;
        s->f_bsize = 1024;
        s->f_blocks = 32768; 
        s->f_bfree = s->f_bavail = 16384;
    }
}

int statvfs(const char *path, struct statvfs *buf) {
    static int (*o)(const char*, struct statvfs*) = NULL;
    if (!o) o = dlsym(RTLD_NEXT, "statvfs");
    int r = o(path, buf);
    apply_fake_stats(buf, 1);
    return 0;
}

int fstatfs64(int fd, struct statfs64 *buf) {
    static int (*o)(int, struct statfs64*) = NULL;
    if (!o) o = dlsym(RTLD_NEXT, "fstatfs64");
    int r = o(fd, buf);
    apply_fake_stats(buf, 0);
    return 0;
}

int fstatfs(int fd, struct statfs *buf) {
    static int (*o)(int, struct statfs*) = NULL;
    if (!o) o = dlsym(RTLD_NEXT, "fstatfs");
    int r = o(fd, buf);
    apply_fake_stats(buf, 0);
    return 0;
}