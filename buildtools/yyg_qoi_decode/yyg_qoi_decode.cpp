/*
 * yyg_qoi_decode: externalize GameMaker 2zoq textures end-to-end.
 *
 *     DATA.WIN -> for each 2zoq blob in the TXTR chunk:
 *                     bz2 decompress
 *                  -> YYG-QOIF decode
 *                  -> ASTC compress (statically-linked astc-encoder, NEON)
 *                  -> PVR v3 wrap
 *                  -> OUT_DIR/<idx>.pvr
 *                 then compact the TXTR chunk so every entry points at a 2x1
 *                 stub blob that the gmloader-next texhack maps to the .pvr.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#if defined(_WIN32)
#  include <io.h>
#  include <direct.h>
#else
#  include <unistd.h>
#  include <sys/stat.h>
#  include <sys/types.h>
#endif
#include <bzlib.h>
#include <algorithm>
#include <filesystem>
#include <thread>
#include <vector>
#include "astcenc.h"

/* Portability shims for the handful of POSIX bits this tool used to use
 * directly. Threading is now std::thread; file truncation maps to the host
 * CRT call; directory creation goes through std::filesystem. */
static inline int portable_truncate(FILE *f, long long size) {
#if defined(_WIN32)
    return _chsize_s(_fileno(f), size);
#else
    return ftruncate(fileno(f), (off_t)size);
#endif
}

static inline int portable_mkdir(const char *path) {
    std::error_code ec;
    std::filesystem::create_directories(path, ec);
    /* Match the old mkdir() contract: 0 on success or "already exists",
     * non-zero on real failure. create_directories returns false when the
     * directory already exists but does not set ec, so check ec only. */
    return ec ? -1 : 0;
}


/* PVR3 pixel_format low-DWORD codes the gmloader-next texhack accepts. */
static const struct block_info {
    const char *name;
    int bx, by;
    uint64_t pvr_code;
} BLOCKS[] = {
    {"4x4", 4, 4, 0x1B},
    {"5x5", 5, 5, 0x1D},
    {"6x6", 6, 6, 0x1F},
    {NULL,  0, 0, 0},
};

#pragma pack(push, 1)
typedef struct {
    uint32_t version;
    uint32_t flags;
    uint64_t pixel_format;
    uint32_t colour_space;
    uint32_t channel_type;
    uint32_t height;
    uint32_t width;
    uint32_t depth;
    uint32_t num_surfaces;
    uint32_t num_faces;
    uint32_t mip_count;
    uint32_t metadata_size;
} pvr3_header_t;
#pragma pack(pop)


/* ---------- YYG-QOIF decoder ---------- */

static inline int sx(unsigned v, int bits) {
    int mask = (1 << bits) - 1;
    int x = (int)(v & (unsigned)mask);
    if (x & (1 << (bits - 1))) x -= (1 << bits);
    return x;
}

static inline unsigned yyg_hash(uint32_t p) {
    return (p ^ (p >> 8) ^ (p >> 16) ^ (p >> 24)) & 0x3F;
}

static int decode_yyg_qoif(const uint8_t *qoif, size_t qoif_len,
                            uint8_t **out_rgba, int *out_w, int *out_h)
{
    if (qoif_len < 12) return -1;
    if (memcmp(qoif, "fioq", 4) != 0) return -2;

    int w = qoif[4] | (qoif[5] << 8);
    int h = qoif[6] | (qoif[7] << 8);
    if (w <= 0 || h <= 0) return -3;

    size_t total_px = (size_t)w * (size_t)h;
    uint8_t *rgba = (uint8_t *)malloc(total_px * 4);
    if (!rgba) return -4;

    const uint8_t *p = qoif + 12;
    const uint8_t *end = qoif + qoif_len;

    uint8_t pixel[4] = { 0, 0, 0, 0xFF };
    uint8_t index[64][4];
    memset(index, 0, sizeof(index));

    size_t out_pos = 0;
    size_t n_px = 0;

#define NEED(n) do { if (end - p < (n)) { free(rgba); return -5; } } while (0)

    while (n_px < total_px && p < end) {
        uint8_t b1 = *p++;
        int run = 0;
        int update_cache = 1;

        if (b1 < 0x40) {
            memcpy(pixel, index[b1], 4);
            update_cache = 0;
        } else if (b1 < 0x60) {
            run = b1 & 0x1F;
            update_cache = 0;
        } else if (b1 < 0x80) {
            NEED(1);
            uint8_t b2 = *p++;
            run = (((b1 & 0x1F) << 8) | b2) + 32;
            update_cache = 0;
        } else if (b1 < 0xC0) {
            pixel[0] = (uint8_t)(pixel[0] + sx((b1 >> 4) & 0x3, 2));
            pixel[1] = (uint8_t)(pixel[1] + sx((b1 >> 2) & 0x3, 2));
            pixel[2] = (uint8_t)(pixel[2] + sx( b1       & 0x3, 2));
        } else if (b1 < 0xE0) {
            NEED(1);
            uint8_t b2 = *p++;
            pixel[0] = (uint8_t)(pixel[0] + sx(b1 & 0x1F, 5));
            pixel[1] = (uint8_t)(pixel[1] + sx((b2 >> 4) & 0xF, 4));
            pixel[2] = (uint8_t)(pixel[2] + sx( b2       & 0xF, 4));
        } else if (b1 < 0xF0) {
            NEED(2);
            uint8_t b2 = *p++;
            uint8_t b3 = *p++;
            int dR  = sx(((b1 & 0xF) << 1) | ((b2 >> 7) & 1), 5);
            int dGs = sx(b2 & 0x7F, 7);
            int dG  = dGs >> 2;
            int dBs = sx(((b2 & 0x3) << 8) | b3, 10);
            int dB  = dBs >> 5;
            int dA  = sx(b3 & 0x1F, 5);
            pixel[0] = (uint8_t)(pixel[0] + dR);
            pixel[1] = (uint8_t)(pixel[1] + dG);
            pixel[2] = (uint8_t)(pixel[2] + dB);
            pixel[3] = (uint8_t)(pixel[3] + dA);
        } else {
            int mask = b1 & 0x0F;
            if (mask & 0x8) { NEED(1); pixel[0] = *p++; }
            if (mask & 0x4) { NEED(1); pixel[1] = *p++; }
            if (mask & 0x2) { NEED(1); pixel[2] = *p++; }
            if (mask & 0x1) { NEED(1); pixel[3] = *p++; }
        }

        if (update_cache) {
            uint32_t pix32 = (uint32_t)pixel[0]
                          | ((uint32_t)pixel[1] << 8)
                          | ((uint32_t)pixel[2] << 16)
                          | ((uint32_t)pixel[3] << 24);
            memcpy(index[yyg_hash(pix32)], pixel, 4);
        }

        memcpy(rgba + out_pos, pixel, 4);
        out_pos += 4;
        n_px++;

        for (int i = 0; i < run && n_px < total_px; i++) {
            memcpy(rgba + out_pos, pixel, 4);
            out_pos += 4;
            n_px++;
        }
    }

#undef NEED

    if (n_px != total_px) {
        fprintf(stderr, "  WARN decoded %zu/%zu pixels\n", n_px, total_px);
    }

    *out_rgba = rgba;
    *out_w = w;
    *out_h = h;
    return 0;
}


/* ---------- bz2 unwrap ---------- */

/* Decompress all bz2 streams in `blob` into a freshly-allocated qoif buffer
 * of the declared decomp_size. Handles concatenated streams. */
static int parse_2zoq(const uint8_t *blob, size_t blob_len,
                      uint8_t **qoif_out, size_t *qoif_len_out)
{
    if (blob_len < 12) return -1;
    if (memcmp(blob, "2zoq", 4) != 0) return -2;

    uint32_t decomp_size = (uint32_t)blob[8]
                        | ((uint32_t)blob[ 9] <<  8)
                        | ((uint32_t)blob[10] << 16)
                        | ((uint32_t)blob[11] << 24);
    uint8_t *qoif = (uint8_t *)malloc(decomp_size);
    if (!qoif) return -3;

    const uint8_t *in = blob + 12;
    size_t in_left = blob_len - 12;
    size_t produced = 0;

    while (produced < decomp_size) {
        bz_stream s;
        memset(&s, 0, sizeof(s));
        if (BZ2_bzDecompressInit(&s, 0, 0) != BZ_OK) {
            free(qoif);
            return -4;
        }
        s.next_in   = (char *)in;
        s.avail_in  = (unsigned int)in_left;
        s.next_out  = (char *)(qoif + produced);
        s.avail_out = (unsigned int)(decomp_size - produced);

        int r;
        do { r = BZ2_bzDecompress(&s); }
        while (r == BZ_OK && s.avail_out > 0);

        size_t consumed = in_left - s.avail_in;
        size_t produced_now = (decomp_size - produced) - s.avail_out;
        BZ2_bzDecompressEnd(&s);

        produced += produced_now;
        in       += consumed;
        in_left  -= consumed;

        if (r == BZ_STREAM_END) {
            if (produced < decomp_size && in_left == 0) {
                free(qoif);
                return -5;
            }
            continue;
        }
        if (r != BZ_OK || produced_now == 0) {
            free(qoif);
            return -6;
        }
    }

    *qoif_out = qoif;
    *qoif_len_out = decomp_size;
    return 0;
}


/* Scan-only: decompress the bz2 streams discarding output, return the total
 * blob length (header + bz2 payload) consumed in src. 0 = false-positive
 * magic / invalid bz2. Lets us walk the TXTR chunk forward when we only need
 * offsets, not data. */
static size_t scan_2zoq_blob_len(const uint8_t *src, size_t src_left) {
    if (src_left < 12 || memcmp(src, "2zoq", 4) != 0) return 0;

    uint32_t decomp_size = (uint32_t)src[8]
                        | ((uint32_t)src[ 9] <<  8)
                        | ((uint32_t)src[10] << 16)
                        | ((uint32_t)src[11] << 24);
    const uint8_t *in = src + 12;
    size_t in_left = src_left - 12;
    size_t produced = 0;
    uint8_t scratch[16384];

    while (produced < decomp_size) {
        bz_stream s;
        memset(&s, 0, sizeof(s));
        if (BZ2_bzDecompressInit(&s, 0, 0) != BZ_OK) return 0;
        s.next_in   = (char *)in;
        s.avail_in  = (unsigned int)in_left;
        s.next_out  = (char *)scratch;
        s.avail_out = sizeof(scratch);

        int r;
        for (;;) {
            r = BZ2_bzDecompress(&s);
            produced += sizeof(scratch) - s.avail_out;
            if (r == BZ_STREAM_END || r != BZ_OK) break;
            s.next_out = (char *)scratch;
            s.avail_out = sizeof(scratch);
        }
        size_t consumed = in_left - s.avail_in;
        BZ2_bzDecompressEnd(&s);

        in      += consumed;
        in_left -= consumed;

        if (r == BZ_STREAM_END) continue;
        if (r != BZ_OK) return 0;
    }
    return (size_t)(in - src);
}


/* ---------- TXTR walk ---------- */

static int find_txtr(const uint8_t *buf, size_t buf_len,
                     size_t *payload_start, size_t *payload_size)
{
    if (buf_len < 8 || memcmp(buf, "FORM", 4) != 0) return -1;
    size_t i = 8;
    while (i + 8 <= buf_len) {
        uint32_t csize = (uint32_t)buf[i+4]
                      | ((uint32_t)buf[i+5] <<  8)
                      | ((uint32_t)buf[i+6] << 16)
                      | ((uint32_t)buf[i+7] << 24);
        if (memcmp(buf + i, "TXTR", 4) == 0) {
            if (i + 8 + csize > buf_len) return -2;
            *payload_start = i + 8;
            *payload_size  = csize;
            return 0;
        }
        i += 8 + csize;
    }
    return -3;
}

static size_t find_next_zoq(const uint8_t *buf, size_t start, size_t end) {
    for (size_t i = start; i + 4 <= end; i++) {
        if (buf[i] == '2' && buf[i+1] == 'z' && buf[i+2] == 'o' && buf[i+3] == 'q')
            return i;
    }
    return (size_t)-1;
}


/* ---------- 2zoq stub builder ---------- */

/* Build a minimum 2zoq blob (~60-70B) whose decoded image is 2x1 RGBA:
 * pixel0 = DE AD BE FF (the texhack magic), pixel1 = idx in low 24 bits.
 * Caller frees *out. */
static int build_2zoq_stub(unsigned int idx, uint8_t **out, size_t *out_len) {
    uint8_t qoif[64];
    size_t q = 0;
    memcpy(qoif + q, "fioq", 4); q += 4;
    qoif[q++] = 2; qoif[q++] = 0;
    qoif[q++] = 1; qoif[q++] = 0;
    qoif[q++] = 0x04; qoif[q++] = 0;
    qoif[q++] = 0;    qoif[q++] = 0;
    qoif[q++] = 0xFF;
    qoif[q++] = 0xDE;
    qoif[q++] = 0xAD;
    qoif[q++] = 0xBE;
    qoif[q++] = 0xFF;
    qoif[q++] = 0xFF;
    qoif[q++] = (uint8_t)(idx & 0xFF);
    qoif[q++] = (uint8_t)((idx >> 8) & 0xFF);
    qoif[q++] = (uint8_t)((idx >> 16) & 0xFF);
    qoif[q++] = 0xFF;
    memset(qoif + q, 0, 7); q += 7;
    qoif[q++] = 0x01;

    unsigned int bz_cap = (unsigned int)(q + (q / 100) + 600);
    uint8_t *bz_buf = (uint8_t *)malloc(bz_cap);
    if (!bz_buf) return -1;
    int r = BZ2_bzBuffToBuffCompress((char *)bz_buf, &bz_cap,
                                      (char *)qoif, (unsigned int)q, 9, 0, 30);
    if (r != BZ_OK) { free(bz_buf); return -2; }

    size_t total = 12 + bz_cap;
    uint8_t *stub = (uint8_t *)malloc(total);
    if (!stub) { free(bz_buf); return -1; }
    memcpy(stub, "2zoq", 4);
    stub[4] = 2; stub[5] = 0;
    stub[6] = 1; stub[7] = 0;
    stub[ 8] = (uint8_t)(q & 0xFF);
    stub[ 9] = (uint8_t)((q >> 8) & 0xFF);
    stub[10] = (uint8_t)((q >> 16) & 0xFF);
    stub[11] = (uint8_t)((q >> 24) & 0xFF);
    memcpy(stub + 12, bz_buf, bz_cap);
    free(bz_buf);

    *out = stub;
    *out_len = total;
    return 0;
}


/* ---------- strip tiling ---------- */

static int compute_strip_heights(int w, int h, int block_dim, size_t max_px,
                                  int **heights_out, int *n_out)
{
    int pad_h = ((h + block_dim - 1) / block_dim) * block_dim;
    if (max_px == 0 || (size_t)w * (size_t)h <= max_px) {
        int *r = (int *)malloc(sizeof(int));
        if (!r) return -1;
        r[0] = pad_h;
        *heights_out = r;
        *n_out = 1;
        return 0;
    }
    int max_strip = (int)(max_px / (size_t)w);
    max_strip = (max_strip / block_dim) * block_dim;
    if (max_strip <= 0) return -2;

    int n = 0, rem = h;
    while (rem > max_strip) { n++; rem -= max_strip; }
    if (rem > 0) n++;

    int *r = (int *)malloc((size_t)n * sizeof(int));
    if (!r) return -1;
    int i = 0;
    rem = h;
    while (rem > max_strip) { r[i++] = max_strip; rem -= max_strip; }
    if (rem > 0) r[i++] = ((rem + block_dim - 1) / block_dim) * block_dim;
    *heights_out = r;
    *n_out = n;
    return 0;
}


/* ---------- ASTC compression ---------- */

struct astc_thread_arg {
    astcenc_context *ctx;
    astcenc_image *image;
    const astcenc_swizzle *swizzle;
    uint8_t *payload;
    size_t payload_len;
    unsigned int thread_id;
    astcenc_error err;
};

static void *astc_thread_fn(void *p) {
    struct astc_thread_arg *a = (struct astc_thread_arg *)p;
    a->err = astcenc_compress_image(a->ctx, a->image, a->swizzle,
                                    a->payload, a->payload_len, a->thread_id);
    return NULL;
}

/* Allocate an astcenc context for a (block, quality, threads) tuple. The
 * context is the expensive bit -- it allocates internal tables and is
 * documented as costly. Reusing the context across many compresses (which
 * we do per-atlas in --repack mode) saves ~50-200ms per atlas. */
static astcenc_context *astc_make_context(int block_x, int block_y,
                                           float quality, unsigned threads)
{
    astcenc_config config;
    astcenc_error err = astcenc_config_init(ASTCENC_PRF_LDR_SRGB,
        (unsigned)block_x, (unsigned)block_y, 1, quality, 0, &config);
    if (err != ASTCENC_SUCCESS) {
        fprintf(stderr, "astcenc_config_init failed: %d\n", err);
        return NULL;
    }
    astcenc_context *ctx = NULL;
    err = astcenc_context_alloc(&config, threads, &ctx);
    if (err != ASTCENC_SUCCESS) {
        fprintf(stderr, "astcenc_context_alloc failed: %d\n", err);
        return NULL;
    }
    return ctx;
}

static int astc_compress_strip(const uint8_t *src_rgba, int full_w, int full_h,
                               int y_start, int strip_h,
                               int block_x, int block_y,
                               astcenc_context *ctx, unsigned threads,
                               uint8_t *payload_out, size_t payload_cap,
                               size_t *payload_written)
{
    size_t stride = (size_t)full_w * 4;
    uint8_t *strip_buf = (uint8_t *)malloc((size_t)strip_h * stride);
    if (!strip_buf) return -1;
    for (int y = 0; y < strip_h; y++) {
        int src_y = y_start + y;
        if (src_y >= full_h) src_y = full_h - 1;
        memcpy(strip_buf + (size_t)y * stride,
               src_rgba + (size_t)src_y * stride, stride);
    }

    void *slice_ptrs[1] = { strip_buf };
    astcenc_image image;
    image.dim_x = (unsigned)full_w;
    image.dim_y = (unsigned)strip_h;
    image.dim_z = 1;
    image.data_type = ASTCENC_TYPE_U8;
    image.data = slice_ptrs;

    astcenc_swizzle sw = { ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A };

    int bx = (full_w + block_x - 1) / block_x;
    int by = (strip_h + block_y - 1) / block_y;
    size_t needed = (size_t)bx * (size_t)by * 16;
    if (needed > payload_cap) {
        free(strip_buf);
        return -4;
    }

    /* Clear any residual internal state from a previous compress on this ctx. */
    astcenc_compress_reset(ctx);

    int ret = 0;
    astcenc_error err;
    if (threads <= 1) {
        err = astcenc_compress_image(ctx, &image, &sw, payload_out, needed, 0);
        if (err != ASTCENC_SUCCESS) ret = -5;
    } else {
        std::vector<astc_thread_arg> args(threads);
        std::vector<std::thread> tids;
        tids.reserve(threads);
        for (unsigned i = 0; i < threads; i++) {
            args[i].ctx         = ctx;
            args[i].image       = &image;
            args[i].swizzle     = &sw;
            args[i].payload     = payload_out;
            args[i].payload_len = needed;
            args[i].thread_id   = i;
            args[i].err         = ASTCENC_SUCCESS;
            try {
                tids.emplace_back(astc_thread_fn, &args[i]);
            } catch (...) {
                ret = -6;
                break;
            }
        }
        for (auto &t : tids) t.join();
        if (ret == 0) {
            for (auto &a : args) {
                if (a.err != ASTCENC_SUCCESS) { ret = -5; break; }
            }
        }
    }

    free(strip_buf);
    if (ret == 0 && payload_written) *payload_written = needed;
    return ret;
}


/* ---------- PVR3 writer ---------- */

static int write_pvr3(const char *path, const uint8_t *payload, size_t payload_len,
                      int width, int height, uint64_t pvr_code)
{
    pvr3_header_t h;
    memset(&h, 0, sizeof(h));
    h.version       = 0x03525650;
    h.pixel_format  = pvr_code;
    h.height        = (uint32_t)height;
    h.width         = (uint32_t)width;
    h.depth         = 1;
    h.num_surfaces  = 1;
    h.num_faces     = 1;
    h.mip_count     = 1;

    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); return -1; }
    if (fwrite(&h, 1, sizeof(h), f) != sizeof(h)) { perror("hdr");     fclose(f); return -1; }
    if (fwrite(payload, 1, payload_len, f) != payload_len)
        { perror("payload"); fclose(f); return -1; }
    if (fclose(f) != 0) { perror("fclose"); return -1; }
    return 0;
}


/* ---------- per-blob pipeline ---------- */

/* Compress an in-memory RGBA buffer to a PVR3 ASTC file. Caller owns the
 * astcenc context (set up via astc_make_context) -- this lets the repacker
 * reuse one context across all 500+ atlases instead of paying setup cost
 * each time. */
static int compress_rgba_to_pvr(const uint8_t *rgba, int w, int h,
                                 const char *out_path,
                                 const struct block_info *blk,
                                 astcenc_context *ctx, unsigned threads,
                                 size_t max_strip)
{
    int *strip_h_arr = NULL;
    int n_strips = 0;
    int r = compute_strip_heights(w, h, blk->by, max_strip,
                                  &strip_h_arr, &n_strips);
    if (r != 0) {
        fprintf(stderr, "compute_strip_heights failed: %d\n", r);
        return -1;
    }

    int blocks_x = (w + blk->bx - 1) / blk->bx;
    size_t total_payload = 0;
    for (int i = 0; i < n_strips; i++) {
        int blocks_y = (strip_h_arr[i] + blk->by - 1) / blk->by;
        total_payload += (size_t)blocks_x * (size_t)blocks_y * 16;
    }
    uint8_t *payload = (uint8_t *)malloc(total_payload);
    if (!payload) {
        fprintf(stderr, "malloc payload %zu failed\n", total_payload);
        free(strip_h_arr); return -1;
    }

    size_t pos = 0;
    int y_start = 0;
    for (int i = 0; i < n_strips; i++) {
        int sh = strip_h_arr[i];
        size_t written = 0;
        r = astc_compress_strip(rgba, w, h, y_start, sh,
                                blk->bx, blk->by, ctx, threads,
                                payload + pos, total_payload - pos, &written);
        if (r != 0) {
            fprintf(stderr, "astc_compress_strip %d/%d failed: %d\n",
                    i + 1, n_strips, r);
            free(payload); free(strip_h_arr); return -1;
        }
        pos += written;
        y_start += sh;
    }
    free(strip_h_arr);

    r = write_pvr3(out_path, payload, pos, w, h, blk->pvr_code);
    free(payload);
    return r;
}

static int compress_blob_to_pvr(const uint8_t *blob, size_t blob_len,
                                 const char *out_path,
                                 const struct block_info *blk,
                                 astcenc_context *ctx, unsigned threads,
                                 size_t max_strip)
{
    uint8_t *qoif = NULL;
    size_t qoif_len = 0;
    int r = parse_2zoq(blob, blob_len, &qoif, &qoif_len);
    if (r != 0) { fprintf(stderr, "parse_2zoq failed: %d\n", r); return -1; }

    uint8_t *rgba = NULL;
    int w = 0, h = 0;
    r = decode_yyg_qoif(qoif, qoif_len, &rgba, &w, &h);
    free(qoif);
    if (r != 0) { fprintf(stderr, "decode_yyg_qoif failed: %d\n", r); return -1; }

    r = compress_rgba_to_pvr(rgba, w, h, out_path, blk, ctx, threads, max_strip);
    free(rgba);
    return r;
}


/* ---------- TXTR compactor ---------- */

/* Repack TXTR: keep the entry table at its original offsets, pack stubs right
 * after the last entry, update each entry's BlobOffset/BlobSize, shift the
 * tail of the file up, truncate, fix the FORM size header. Returns the new
 * total file size, or 0 on error. */
static long compact_txtr(FILE *f, size_t txtr_start, size_t txtr_size,
                         uint8_t **stubs, size_t *stub_lens, unsigned int count)
{
    fseek(f, (long)txtr_start, SEEK_SET);
    uint32_t got;
    if (fread(&got, 4, 1, f) != 1) return 0;
    if (got != count) {
        fprintf(stderr, "TXTR count mismatch: file=%u, expected=%u\n", got, count);
        return 0;
    }

    uint32_t *ptrs = (uint32_t *)malloc(count * sizeof(uint32_t));
    if (!ptrs) return 0;
    if (fread(ptrs, 4, count, f) != count) { free(ptrs); return 0; }

    uint32_t (*entries)[4] = (uint32_t (*)[4])malloc(count * sizeof(*entries));
    if (!entries) { free(ptrs); return 0; }
    for (unsigned int i = 0; i < count; i++) {
        fseek(f, ptrs[i], SEEK_SET);
        if (fread(entries[i], 4, 4, f) != 4) {
            free(entries); free(ptrs); return 0;
        }
    }

    uint32_t entries_end = 0;
    for (unsigned int i = 0; i < count; i++) {
        if (ptrs[i] > entries_end) entries_end = ptrs[i];
    }
    entries_end += 16;

    uint64_t blob_cursor = entries_end;
    for (unsigned int i = 0; i < count; i++) {
        entries[i][2] = (uint32_t)stub_lens[i];
        entries[i][3] = (uint32_t)blob_cursor;
        blob_cursor += stub_lens[i];
    }
    uint64_t new_payload_size = blob_cursor - txtr_start;
    if (new_payload_size > txtr_size) {
        fprintf(stderr, "Compact would grow TXTR; not safe (%" PRIu64 " > %zu)\n",
                new_payload_size, txtr_size);
        free(entries); free(ptrs); return 0;
    }

    fseek(f, 0, SEEK_END);
    long total = ftell(f);
    long tail_start = (long)(txtr_start + txtr_size);
    long tail_len = total - tail_start;
    uint8_t *tail = NULL;
    if (tail_len > 0) {
        tail = (uint8_t *)malloc((size_t)tail_len);
        if (!tail) { free(entries); free(ptrs); return 0; }
        fseek(f, tail_start, SEEK_SET);
        if (fread(tail, 1, (size_t)tail_len, f) != (size_t)tail_len) {
            free(tail); free(entries); free(ptrs); return 0;
        }
    }

    uint32_t new_pls32 = (uint32_t)new_payload_size;
    fseek(f, (long)txtr_start - 4, SEEK_SET);
    fwrite(&new_pls32, 4, 1, f);

    for (unsigned int i = 0; i < count; i++) {
        fseek(f, ptrs[i], SEEK_SET);
        fwrite(entries[i], 4, 4, f);
    }

    fseek(f, entries_end, SEEK_SET);
    for (unsigned int i = 0; i < count; i++) {
        fwrite(stubs[i], 1, stub_lens[i], f);
    }

    long new_tail_start = (long)(txtr_start + new_payload_size);
    if (tail_len > 0) {
        fseek(f, new_tail_start, SEEK_SET);
        fwrite(tail, 1, (size_t)tail_len, f);
        free(tail);
    }
    long new_total = new_tail_start + tail_len;

    fflush(f);
    if (portable_truncate(f, (long long)new_total) != 0) {
        perror("ftruncate"); free(entries); free(ptrs); return 0;
    }

    uint32_t form_size = (uint32_t)(new_total - 8);
    fseek(f, 4, SEEK_SET);
    fwrite(&form_size, 4, 1, f);

    free(entries);
    free(ptrs);
    return new_total;
}


/* ---------- repacker: TPAG/TXTR walk + bin-pack ----------
 *
 * Port of NewTextureRepacker.csx's Best-Long-Side-fit bin-packer plus enough
 * UndertaleModLib parsing to read TPAG records and walk TXTR EmbeddedTexture
 * records by hand.
 */

struct rect_t { int x, y, w, h; };

struct split_t {
    int x, y, w, h;
    bool invalidated;
    int right() const { return x + w; }
    int down()  const { return y + h; }
    bool contains(const rect_t &r) const {
        return r.x >= x && r.y >= y &&
               right() >= r.x + r.w && down() >= r.y + r.h;
    }
    bool overlaps(const rect_t &r) const {
        bool x_ov = (r.x >= x && r.x <= right()) ||
                    (x   >= r.x && x   <= r.x + r.w);
        bool y_ov = (r.y >= y && r.y <= down())  ||
                    (y   >= r.y && y   <= r.y + r.h);
        return x_ov && y_ov;
    }
    bool fits(int W, int H) const { return w >= W && h >= H; }
};

struct atlas_t {
    int w, h;
    std::vector<split_t> splits;
    std::vector<int> tpi_indices;     /* TPIs assigned to this atlas */
};

/* Best-Long-Side-fit allocation in an atlas. On success returns true and
 * fills *out (final position, no padding) and mutates the splits list. */
static bool atlas_allocate(atlas_t &a, int width, int height, int padding,
                           rect_t *out)
{
    int pw = width + 2 * padding;
    int ph = height + 2 * padding;
    int best = -1;
    int best_score = INT_MAX;
    for (size_t i = 0; i < a.splits.size(); i++) {
        if (!a.splits[i].fits(pw, ph)) continue;
        int score = std::max(a.splits[i].w - pw, a.splits[i].h - ph);
        if (score < best_score) { best_score = score; best = (int)i; }
    }
    if (best < 0) return false;

    rect_t r = { a.splits[best].x, a.splits[best].y, pw, ph };
    std::vector<split_t> new_splits;
    for (auto &s : a.splits) {
        if (s.invalidated || !s.overlaps(r)) continue;
        s.invalidated = true;
        /* up    */ if (r.y - s.y > 0)
            new_splits.push_back({s.x, s.y, s.w, r.y - s.y, false});
        /* left  */ if (r.x - s.x > 0)
            new_splits.push_back({s.x, s.y, r.x - s.x, s.h, false});
        /* down  */ if (s.down() - (r.y + r.h) > 0)
            new_splits.push_back({s.x, r.y + r.h, s.w, s.down() - (r.y + r.h), false});
        /* right */ if (s.right() - (r.x + r.w) > 0)
            new_splits.push_back({r.x + r.w, s.y, s.right() - (r.x + r.w), s.h, false});
    }
    a.splits.erase(std::remove_if(a.splits.begin(), a.splits.end(),
                                  [](const split_t &s){ return s.invalidated; }),
                   a.splits.end());
    a.splits.insert(a.splits.end(), new_splits.begin(), new_splits.end());

    /* Drop any split fully contained inside another. */
    for (size_t i = 0; i < a.splits.size(); i++) {
        if (a.splits[i].invalidated) continue;
        for (size_t j = 0; j < a.splits.size(); j++) {
            if (i == j || a.splits[j].invalidated) continue;
            rect_t r2 = { a.splits[j].x, a.splits[j].y,
                          a.splits[j].w, a.splits[j].h };
            if (a.splits[i].contains(r2)) a.splits[j].invalidated = true;
        }
    }
    a.splits.erase(std::remove_if(a.splits.begin(), a.splits.end(),
                                  [](const split_t &s){ return s.invalidated; }),
                   a.splits.end());

    out->x = r.x + padding;
    out->y = r.y + padding;
    out->w = width;
    out->h = height;
    return true;
}


/* TexturePageItem: 22-byte UndertaleModLib record. */
struct tpi_t {
    long file_offset;       /* offset of the 22-byte record in data.win */
    uint16_t source_x, source_y, source_w, source_h;
    uint16_t target_x, target_y, target_w, target_h;
    uint16_t bounding_w, bounding_h;
    int16_t  orig_page_idx; /* original TexturePage index */

    /* Filled in by the bin-packer pass: */
    int new_page_idx;       /* index into the new atlases list */
    rect_t new_rect;
};

/* Source page descriptor (one per original TXTR EmbeddedTexture). Just enough
 * to find its 2zoq blob and remember its Scaled / Mips for new-atlas inherit. */
struct src_page_t {
    long blob_offset;       /* file offset of the 2zoq blob */
    size_t blob_len;        /* scanned blob length */
    uint32_t scaled;
    uint32_t generated_mips;
    int w, h;               /* decoded dimensions (read lazily from QOIF hdr) */
};


/* Find a chunk by name in a FORM/IFF file. Returns 0 and sets start/size on
 * success, -1 if not found. */
static int find_chunk(const uint8_t *buf, size_t buf_len, const char *name,
                     size_t *out_start, size_t *out_size)
{
    if (buf_len < 8 || memcmp(buf, "FORM", 4) != 0) return -1;
    size_t i = 8;
    while (i + 8 <= buf_len) {
        uint32_t csize = (uint32_t)buf[i+4]
                      | ((uint32_t)buf[i+5] <<  8)
                      | ((uint32_t)buf[i+6] << 16)
                      | ((uint32_t)buf[i+7] << 24);
        if (memcmp(buf + i, name, 4) == 0) {
            if (i + 8 + csize > buf_len) return -1;
            *out_start = i + 8;
            *out_size  = csize;
            return 0;
        }
        i += 8 + csize;
    }
    return -1;
}


/* Walk TPAG: u32 count, u32 ptrs[count], records at the pointed offsets.
 * Each record is 22 bytes (see UndertaleTexturePageItem.Unserialize). */
static int parse_tpag(const uint8_t *win, size_t win_len,
                     std::vector<tpi_t> &out_tpis)
{
    size_t tpag_start, tpag_size;
    if (find_chunk(win, win_len, "TPAG", &tpag_start, &tpag_size) != 0) {
        fprintf(stderr, "No TPAG chunk.\n");
        return -1;
    }
    const uint8_t *p = win + tpag_start;
    uint32_t count = (uint32_t)p[0] | ((uint32_t)p[1] <<  8)
                  | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    p += 4;
    out_tpis.reserve(count);
    for (uint32_t i = 0; i < count; i++) {
        uint32_t ptr = (uint32_t)p[0] | ((uint32_t)p[1] <<  8)
                    | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
        p += 4;
        if (ptr + 22 > win_len) {
            fprintf(stderr, "TPAG entry %u ptr 0x%x out of range\n", i, ptr);
            return -2;
        }
        const uint8_t *r = win + ptr;
        tpi_t t;
        t.file_offset    = (long)ptr;
        t.source_x       = r[ 0] | (r[ 1] << 8);
        t.source_y       = r[ 2] | (r[ 3] << 8);
        t.source_w       = r[ 4] | (r[ 5] << 8);
        t.source_h       = r[ 6] | (r[ 7] << 8);
        t.target_x       = r[ 8] | (r[ 9] << 8);
        t.target_y       = r[10] | (r[11] << 8);
        t.target_w       = r[12] | (r[13] << 8);
        t.target_h       = r[14] | (r[15] << 8);
        t.bounding_w     = r[16] | (r[17] << 8);
        t.bounding_h     = r[18] | (r[19] << 8);
        t.orig_page_idx  = (int16_t)(r[20] | (r[21] << 8));
        t.new_page_idx   = -1;
        t.new_rect       = {0, 0, 0, 0};
        out_tpis.push_back(t);
    }
    return 0;
}


/* Walk TXTR pointer table + 16-byte EmbeddedTexture records (GMS 2022.3-8
 * layout; same one the existing compact_txtr assumes). Pairs each entry with
 * its 2zoq blob (found by scanning forward from the data pointer). */
static int parse_txtr_pages(const uint8_t *win, size_t win_len,
                           std::vector<src_page_t> &out_pages)
{
    size_t txtr_start, txtr_size;
    if (find_chunk(win, win_len, "TXTR", &txtr_start, &txtr_size) != 0) {
        fprintf(stderr, "No TXTR chunk.\n");
        return -1;
    }
    const uint8_t *base = win + txtr_start;
    uint32_t count = (uint32_t)base[0] | ((uint32_t)base[1] <<  8)
                  | ((uint32_t)base[2] << 16) | ((uint32_t)base[3] << 24);
    const uint8_t *ptab = base + 4;
    out_pages.reserve(count);
    for (uint32_t i = 0; i < count; i++) {
        uint32_t rec_off = (uint32_t)ptab[i*4 + 0]
                        | ((uint32_t)ptab[i*4 + 1] <<  8)
                        | ((uint32_t)ptab[i*4 + 2] << 16)
                        | ((uint32_t)ptab[i*4 + 3] << 24);
        if (rec_off + 16 > win_len) {
            fprintf(stderr, "TXTR entry %u ptr out of range\n", i);
            return -2;
        }
        const uint8_t *rec = win + rec_off;
        src_page_t s;
        s.scaled         = (uint32_t)rec[0] | ((uint32_t)rec[1] << 8)
                         | ((uint32_t)rec[2] << 16) | ((uint32_t)rec[3] << 24);
        s.generated_mips = (uint32_t)rec[4] | ((uint32_t)rec[5] << 8)
                         | ((uint32_t)rec[6] << 16) | ((uint32_t)rec[7] << 24);
        uint32_t blob_off = (uint32_t)rec[12] | ((uint32_t)rec[13] << 8)
                          | ((uint32_t)rec[14] << 16) | ((uint32_t)rec[15] << 24);
        s.blob_offset    = (long)blob_off;
        size_t left      = (txtr_start + txtr_size) - (size_t)blob_off;
        s.blob_len       = scan_2zoq_blob_len(win + blob_off, left);
        if (s.blob_len == 0) {
            fprintf(stderr, "TXTR entry %u: 2zoq blob @0x%x not valid\n",
                    i, blob_off);
            return -3;
        }
        /* Width/Height read lazily from QOIF header inside the blob. */
        s.w = win[blob_off + 4] | (win[blob_off + 5] << 8);
        s.h = win[blob_off + 6] | (win[blob_off + 7] << 8);
        out_pages.push_back(s);
    }
    return 0;
}


/* Run the bin-packer over the TPI list. Items that pass the size/area/alone
 * filter get packed into atlases of pageSize x pageSize. Items that don't get
 * their own dedicated atlas (one TPI per atlas, atlas sized exactly to the
 * TPI's source rect). Returns the new atlas list with tpi_indices filled in
 * and mutates `tpis` to set their new_page_idx / new_rect. */
static void run_repacker(std::vector<tpi_t> &tpis,
                         const std::vector<src_page_t> &pages,
                         int page_size, int padding,
                         int max_dims, int max_area,
                         std::vector<atlas_t> &out_atlases)
{
    /* Count TPIs per source page (so we know "alone on page"). */
    std::vector<int> per_page_count(pages.size(), 0);
    for (auto &t : tpis) {
        if (t.orig_page_idx >= 0 && (size_t)t.orig_page_idx < pages.size())
            per_page_count[t.orig_page_idx]++;
    }

    /* Decide which TPIs are eligible for repack (small, shared-page). */
    std::vector<int> repack_idx;
    std::vector<int> solo_idx;
    repack_idx.reserve(tpis.size());
    int rej_dims = 0, rej_area = 0, rej_alone = 0, rej_bad_page = 0, rej_zero = 0;
    for (size_t i = 0; i < tpis.size(); i++) {
        const tpi_t &t = tpis[i];
        bool too_big_dim  = (t.source_w > max_dims || t.source_h > max_dims);
        bool too_big_area = ((int)t.source_w * (int)t.source_h > max_area);
        bool bad_page     = (t.orig_page_idx < 0 ||
                             (size_t)t.orig_page_idx >= pages.size());
        bool zero_size    = (t.source_w == 0 || t.source_h == 0);
        bool alone        = !bad_page && per_page_count[t.orig_page_idx] <= 1;

        if (zero_size)          { rej_zero++;     solo_idx.push_back((int)i); continue; }
        if (bad_page)           { rej_bad_page++; solo_idx.push_back((int)i); continue; }
        if (too_big_dim)        { rej_dims++;     solo_idx.push_back((int)i); continue; }
        if (too_big_area)       { rej_area++;     solo_idx.push_back((int)i); continue; }
        if (alone)              { rej_alone++;    solo_idx.push_back((int)i); continue; }
        repack_idx.push_back((int)i);
    }
    fprintf(stdout,
            "TPI filter: %zu eligible / %zu total\n"
            "  rejected: dims=%d  area=%d  alone-on-page=%d  bad-page=%d  zero=%d\n",
            repack_idx.size(), tpis.size(),
            rej_dims, rej_area, rej_alone, rej_bad_page, rej_zero);
    fflush(stdout);

    /* Sort eligible TPIs by max(w,h) ascending (mimics NewTextureRepacker). */
    std::sort(repack_idx.begin(), repack_idx.end(),
              [&](int a, int b) {
                  int la = std::max(tpis[a].source_w, tpis[a].source_h);
                  int lb = std::max(tpis[b].source_w, tpis[b].source_h);
                  return la < lb;
              });

    /* Pack eligible items into pageSize atlases. */
    std::vector<int> pending = repack_idx;
    while (!pending.empty()) {
        atlas_t a;
        a.w = page_size;
        a.h = page_size;
        a.splits.push_back({0, 0, page_size, page_size, false});

        std::vector<int> leftover;
        for (int idx : pending) {
            rect_t r;
            if (atlas_allocate(a, tpis[idx].source_w, tpis[idx].source_h,
                               padding, &r)) {
                tpis[idx].new_page_idx = (int)out_atlases.size();
                tpis[idx].new_rect    = r;
                a.tpi_indices.push_back(idx);
            } else {
                leftover.push_back(idx);
            }
        }
        if (a.tpi_indices.empty()) {
            /* Nothing fit -- the next item is bigger than the page, bail. */
            for (int idx : pending) solo_idx.push_back(idx);
            break;
        }
        out_atlases.push_back(std::move(a));
        pending.swap(leftover);
    }

    /* Each solo (skipped or too-big) TPI gets a dedicated atlas exactly its
     * source size, position (0, 0). The runtime cost is the same as today. */
    for (int idx : solo_idx) {
        tpi_t &t = tpis[idx];
        atlas_t a;
        a.w = t.source_w;
        a.h = t.source_h;
        a.tpi_indices.push_back(idx);
        t.new_page_idx = (int)out_atlases.size();
        t.new_rect     = {0, 0, t.source_w, t.source_h};
        out_atlases.push_back(std::move(a));
    }
}


/* 2-entry LRU cache for decoded source pages. Sized so peak memory stays
 * bounded at ~2 * max_source_page worth of RGBA (e.g. 32MB for 2048² pages). */
struct page_cache_t {
    struct slot { int page_idx; uint8_t *rgba; int w, h; uint64_t tick; } slots[2];
    uint64_t tick;
};

static void page_cache_init(page_cache_t &c) {
    for (int i = 0; i < 2; i++) { c.slots[i].page_idx = -1; c.slots[i].rgba = NULL;
                                  c.slots[i].w = c.slots[i].h = 0; c.slots[i].tick = 0; }
    c.tick = 0;
}
static void page_cache_free(page_cache_t &c) {
    for (int i = 0; i < 2; i++) { free(c.slots[i].rgba); c.slots[i].rgba = NULL; }
}

/* Returns RGBA pointer (owned by cache, do NOT free). Decodes on miss,
 * evicts LRU slot when both are occupied. */
static int page_cache_get(page_cache_t &c, int page_idx,
                          const uint8_t *win, const src_page_t &src,
                          uint8_t **out_rgba, int *out_w, int *out_h)
{
    c.tick++;
    for (int i = 0; i < 2; i++) {
        if (c.slots[i].page_idx == page_idx && c.slots[i].rgba) {
            c.slots[i].tick = c.tick;
            *out_rgba = c.slots[i].rgba;
            *out_w = c.slots[i].w;
            *out_h = c.slots[i].h;
            return 0;
        }
    }
    /* Miss: decode. */
    uint8_t *qoif = NULL;
    size_t qoif_len = 0;
    int r = parse_2zoq(win + src.blob_offset, src.blob_len, &qoif, &qoif_len);
    if (r != 0) {
        fprintf(stderr, "parse_2zoq(src page) failed: %d\n", r);
        return -1;
    }
    uint8_t *rgba = NULL;
    int w = 0, h = 0;
    r = decode_yyg_qoif(qoif, qoif_len, &rgba, &w, &h);
    free(qoif);
    if (r != 0) {
        fprintf(stderr, "decode_yyg_qoif(src page) failed: %d\n", r);
        return -1;
    }
    /* Evict LRU. */
    int victim = (c.slots[0].tick <= c.slots[1].tick) ? 0 : 1;
    free(c.slots[victim].rgba);
    c.slots[victim].page_idx = page_idx;
    c.slots[victim].rgba = rgba;
    c.slots[victim].w = w;
    c.slots[victim].h = h;
    c.slots[victim].tick = c.tick;
    *out_rgba = rgba;
    *out_w = w;
    *out_h = h;
    return 0;
}

/* Copy `w x h` pixels from src @(src_x, src_y) into dst @(dst_x, dst_y).
 * Both buffers are tightly-packed RGBA8888. Out-of-bounds reads are silently
 * clamped (shouldn't happen with valid TPI rects, but guards against bad
 * data). */
static void composite_crop(uint8_t *dst, int dst_w, int dst_h,
                            int dst_x, int dst_y,
                            const uint8_t *src, int src_w, int src_h,
                            int src_x, int src_y, int w, int h)
{
    if (src_x < 0 || src_y < 0) return;
    if (src_x + w > src_w) w = src_w - src_x;
    if (src_y + h > src_h) h = src_h - src_y;
    if (dst_x + w > dst_w) w = dst_w - dst_x;
    if (dst_y + h > dst_h) h = dst_h - dst_y;
    if (w <= 0 || h <= 0) return;
    size_t row_bytes = (size_t)w * 4;
    for (int y = 0; y < h; y++) {
        memcpy(dst + (size_t)((dst_y + y) * dst_w + dst_x) * 4,
               src + (size_t)((src_y + y) * src_w + src_x) * 4,
               row_bytes);
    }
}


static inline void w_u32_le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v);       p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}
static inline void w_i16_le(uint8_t *p, int16_t v) {
    p[0] = (uint8_t)(v);       p[1] = (uint8_t)(v >> 8);
}

/* Rewrite each TPI's 22-byte record in the win buffer with its new Source
 * rect + TexturePage index. Target/Bounding fields are untouched. */
static void rewrite_tpi_records(uint8_t *win, const std::vector<tpi_t> &tpis) {
    for (const auto &t : tpis) {
        uint8_t *r = win + t.file_offset;
        w_u32_le(r + 0, ((uint32_t)(uint16_t)t.new_rect.y << 16) | (uint16_t)t.new_rect.x);
        w_u32_le(r + 4, ((uint32_t)(uint16_t)t.new_rect.h << 16) | (uint16_t)t.new_rect.w);
        /* bytes 8..19 (Target + Bounding) -- unchanged */
        w_i16_le(r + 20, (int16_t)t.new_page_idx);
    }
}

/* Rebuild the TXTR chunk in place, shift the tail forward, patch the FORM
 * size + chunk size headers, then write the whole win buffer back to disk
 * and truncate. Returns the new file size, or 0 on error. */
static long rebuild_txtr_and_flush(FILE *f, uint8_t *win, size_t win_len,
                                   size_t txtr_start, size_t txtr_size,
                                   const std::vector<atlas_t> &atlases,
                                   const std::vector<tpi_t> &tpis,
                                   const std::vector<src_page_t> &pages)
{
    size_t N = atlases.size();

    /* Build stubs (need their sizes for the record layout). */
    std::vector<std::vector<uint8_t>> stubs(N);
    for (size_t i = 0; i < N; i++) {
        uint8_t *s = NULL; size_t slen = 0;
        if (build_2zoq_stub((unsigned)i, &s, &slen) != 0) {
            fprintf(stderr, "build_2zoq_stub %zu failed\n", i); return 0;
        }
        stubs[i].assign(s, s + slen); free(s);
    }

    /* Pick Scaled/Mips for each new atlas from its first contributor. */
    auto inherit_for = [&](size_t ai) -> std::pair<uint32_t, uint32_t> {
        if (atlases[ai].tpi_indices.empty()) return {0, 0};
        int tpi_idx = atlases[ai].tpi_indices[0];
        int orig_pg = tpis[tpi_idx].orig_page_idx;
        if (orig_pg < 0 || (size_t)orig_pg >= pages.size()) return {0, 0};
        return { pages[orig_pg].scaled, pages[orig_pg].generated_mips };
    };

    /* Layout the new TXTR. Records are tightly packed after the ptr table;
     * each blob is 128-byte aligned (matches UndertaleEmbeddedTexture's
     * UnserializeBlob padding check, and the GMS runtime expects the same). */
    size_t records_offset = txtr_start + 4 + 4 * N;
    size_t stubs_offset   = records_offset + 16 * N;

    std::vector<size_t> stub_pos(N);
    size_t cur = stubs_offset;
    for (size_t i = 0; i < N; i++) {
        while (cur & 0x7F) cur++;     /* 128-byte align before each blob */
        stub_pos[i] = cur;
        cur += stubs[i].size();
    }
    /* 4-byte align the chunk end. */
    while ((cur - txtr_start) & 3u) cur++;
    size_t new_txtr_size = cur - txtr_start;
    if (new_txtr_size > txtr_size) {
        fprintf(stderr, "New TXTR (%zu) is larger than original (%zu)\n",
                new_txtr_size, txtr_size);
        return 0;
    }

    /* Overwrite the TXTR payload region of win[] with the new content. */
    uint8_t *p = win + txtr_start;
    memset(p, 0, new_txtr_size);
    w_u32_le(p, (uint32_t)N);                                /* count */
    for (size_t i = 0; i < N; i++) {                         /* ptr table */
        w_u32_le(p + 4 + 4 * i, (uint32_t)(records_offset + 16 * i));
    }
    for (size_t i = 0; i < N; i++) {                         /* records */
        auto [sc, mp] = inherit_for(i);
        size_t roff = records_offset + 16 * i - txtr_start;
        w_u32_le(p + roff + 0,  sc);
        w_u32_le(p + roff + 4,  mp);
        w_u32_le(p + roff + 8,  (uint32_t)stubs[i].size());
        w_u32_le(p + roff + 12, (uint32_t)stub_pos[i]);
    }
    for (size_t i = 0; i < N; i++) {                         /* stubs */
        memcpy(p + (stub_pos[i] - txtr_start),
               stubs[i].data(), stubs[i].size());
    }

    /* Patch the 4-byte chunk size that lives immediately before payload. */
    w_u32_le(win + txtr_start - 4, (uint32_t)new_txtr_size);

    /* Slide the tail (everything after the original TXTR) forward. */
    size_t tail_start = txtr_start + txtr_size;
    size_t tail_len   = win_len - tail_start;
    size_t new_tail_start = txtr_start + new_txtr_size;
    if (tail_len > 0) {
        memmove(win + new_tail_start, win + tail_start, tail_len);
    }
    size_t new_total = new_tail_start + tail_len;

    /* Patch FORM size at offset 4. */
    w_u32_le(win + 4, (uint32_t)(new_total - 8));

    /* Flush whole buffer to disk and truncate. */
    rewind(f);
    if (fwrite(win, 1, new_total, f) != new_total) { perror("fwrite"); return 0; }
    fflush(f);
    if (portable_truncate(f, (long long)new_total) != 0) { perror("ftruncate"); return 0; }
    return (long)new_total;
}


/* Repack entry point. Walks TPAG + TXTR, bin-packs TPIs into smaller atlases,
 * streams source pages through a 2-entry LRU to composite + ASTC-compress
 * each new atlas, then rewrites TPI records and rebuilds the TXTR chunk so
 * the gmloader-next texhack picks up the new <idx>.pvr externals.
 *
 * `max_dims` / `max_area`: any TPI exceeding either gets its own solo atlas
 * sized exactly to its source rect (the script's escape hatch for shader
 * LUTs and giant single-sprite pages). Pass 0 for either to default to the
 * atlas size -- i.e. anything that could fit in an atlas is eligible. */
static int run_repack(const char *data_win, const char *out_dir,
                      const struct block_info *blk, float quality,
                      size_t max_strip, unsigned threads,
                      int page_size, int max_dims, int max_area)
{
    if (max_dims <= 0) max_dims = page_size;
    if (max_area <= 0) max_area = page_size * page_size;
    FILE *f = fopen(data_win, "r+b");
    if (!f) { perror(data_win); return 3; }
    fseek(f, 0, SEEK_END);
    long total_size = ftell(f);
    rewind(f);
    if (total_size <= 0) { fclose(f); return 3; }

    uint8_t *win = (uint8_t *)malloc((size_t)total_size);
    if (!win) { fclose(f); return 4; }
    if (fread(win, 1, (size_t)total_size, f) != (size_t)total_size) {
        free(win); fclose(f); return 4;
    }

    std::vector<tpi_t> tpis;
    std::vector<src_page_t> pages;
    if (parse_tpag(win, (size_t)total_size, tpis) != 0)        { free(win); fclose(f); return 5; }
    if (parse_txtr_pages(win, (size_t)total_size, pages) != 0) { free(win); fclose(f); return 5; }

    printf("Loaded %zu TPIs from %zu source pages.\n", tpis.size(), pages.size());
    printf("Filter: max_dims=%d, max_area=%d, page_size=%d\n",
           max_dims, max_area, page_size);
    fflush(stdout);

    printf("Bin-packing %zu TPIs into atlases...\n", tpis.size());
    fflush(stdout);

    std::vector<atlas_t> atlases;
    run_repacker(tpis, pages, page_size, /*padding=*/1,
                 max_dims, max_area, atlases);

    size_t n_eligible = 0, n_solo = 0;
    for (auto &a : atlases) (a.tpi_indices.size() > 1 ? n_eligible : n_solo)++;
    printf("Repack plan: %zu new atlases (%zu packed, %zu solo) at <= %dx%d\n",
           atlases.size(), n_eligible, n_solo, page_size, page_size);
    printf("Was: %zu source pages\n", pages.size());
    fflush(stdout);

    /* Pass 2: stream-compose each atlas and emit a PVR. */
    page_cache_t cache;
    page_cache_init(cache);

    /* One astcenc context for the whole run; reused across every atlas. */
    astcenc_context *astc_ctx = astc_make_context(blk->bx, blk->by, quality, threads);
    if (!astc_ctx) {
        page_cache_free(cache);
        free(win); fclose(f); return 6;
    }

    printf("Compressing %zu texture atlases...\n", atlases.size());
    fflush(stdout);
    int last_pct = -1;

    int ret = 0;
    for (size_t ai = 0; ai < atlases.size(); ai++) {
        atlas_t &a = atlases[ai];

        int pct = (int)((ai * 100) / atlases.size());
        if (pct != last_pct) {
            printf("  %3d%%  (atlas %zu/%zu)\n", pct, ai + 1, atlases.size());
            fflush(stdout);
            last_pct = pct;
        }

        /* Source-locality sort so the 2-entry cache earns its keep. */
        std::sort(a.tpi_indices.begin(), a.tpi_indices.end(),
                  [&](int x, int y) {
                      return tpis[x].orig_page_idx < tpis[y].orig_page_idx;
                  });

        size_t atlas_bytes = (size_t)a.w * (size_t)a.h * 4;
        uint8_t *atlas_rgba = (uint8_t *)calloc(1, atlas_bytes);
        if (!atlas_rgba) {
            fprintf(stderr, "OOM allocating atlas %zu (%dx%d)\n", ai, a.w, a.h);
            ret = 6; break;
        }

        for (int tpi_idx : a.tpi_indices) {
            const tpi_t &t = tpis[tpi_idx];
            if (t.orig_page_idx < 0 ||
                (size_t)t.orig_page_idx >= pages.size()) continue;

            uint8_t *src_rgba = NULL;
            int src_w = 0, src_h = 0;
            if (page_cache_get(cache, t.orig_page_idx, win,
                               pages[t.orig_page_idx],
                               &src_rgba, &src_w, &src_h) != 0) {
                fprintf(stderr, "Atlas %zu: failed source page %d\n",
                        ai, t.orig_page_idx);
                free(atlas_rgba); ret = 7; goto pass2_done;
            }
            composite_crop(atlas_rgba, a.w, a.h,
                           t.new_rect.x, t.new_rect.y,
                           src_rgba, src_w, src_h,
                           t.source_x, t.source_y,
                           t.source_w, t.source_h);
        }

        char pvr_path[1024];
        snprintf(pvr_path, sizeof(pvr_path), "%s/%zu.pvr", out_dir, ai);
        if (compress_rgba_to_pvr(atlas_rgba, a.w, a.h, pvr_path,
                                  blk, astc_ctx, threads, max_strip) != 0) {
            fprintf(stderr, "Atlas %zu compress/write failed\n", ai);
            free(atlas_rgba); ret = 8; goto pass2_done;
        }
        free(atlas_rgba);
    }
    printf("  100%%  (atlas %zu/%zu)\n", atlases.size(), atlases.size());
    fflush(stdout);

pass2_done:
    astcenc_context_free(astc_ctx);
    page_cache_free(cache);
    if (ret != 0) { free(win); fclose(f); return ret; }

    /* Rewrite each TPI in place with its new Source rect + page idx. */
    rewrite_tpi_records(win, tpis);

    /* Rebuild TXTR, slide tail, patch FORM size, flush + truncate. */
    size_t txtr_start = 0, txtr_size = 0;
    if (find_chunk(win, (size_t)total_size, "TXTR", &txtr_start, &txtr_size) != 0) {
        fprintf(stderr, "TXTR not found during rewrite\n");
        free(win); fclose(f); return 9;
    }
    long new_total = rebuild_txtr_and_flush(f, win, (size_t)total_size,
                                             txtr_start, txtr_size,
                                             atlases, tpis, pages);
    free(win);
    fclose(f);
    if (new_total == 0) { fprintf(stderr, "TXTR rebuild failed\n"); return 10; }

    printf("Updated %s: %ld -> %ld (%.1f MB saved)\n",
           data_win, total_size, new_total,
           (total_size - new_total) / 1048576.0);
    return 0;
}


/* ---------- CLI ---------- */

static int parse_quality(const char *s, float *q) {
    if (!strcmp(s, "-fast"))      { *q = ASTCENC_PRE_FAST;      return 0; }
    if (!strcmp(s, "-medium"))    { *q = ASTCENC_PRE_MEDIUM;    return 0; }
    if (!strcmp(s, "-thorough"))  { *q = ASTCENC_PRE_THOROUGH;  return 0; }
    if (!strcmp(s, "-fastest"))   { *q = ASTCENC_PRE_FASTEST;   return 0; }
    return -1;
}

static const struct block_info *find_block(const char *s) {
    for (int i = 0; BLOCKS[i].name; i++) {
        if (!strcmp(s, BLOCKS[i].name)) return &BLOCKS[i];
    }
    return NULL;
}

static void usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s DATA.WIN OUT_DIR [opts]\n"
        "  Externalizes every 2zoq texture in DATA.WIN to OUT_DIR/<idx>.pvr\n"
        "  and rewrites DATA.WIN's TXTR chunk to 2x1 stub blobs.\n"
        "\n"
        "  --block 4x4|5x5|6x6                ASTC block size (default 4x4)\n"
        "  --quality -fast|-medium|-thorough  astcenc preset (default -medium)\n"
        "  --max-strip-pixels N               tile w*h > N into strips (default 25000000)\n"
        "  --threads N                        astcenc threads (default = nproc)\n"
        "  --repack                           bin-pack TPIs into smaller atlases\n"
        "  --page-size N                      atlas size when --repack (default 512)\n"
        "  --max-dims N                       solo any TPI with w>N or h>N (default = page-size)\n"
        "  --max-area N                       solo any TPI with w*h>N (default = page-size^2)\n"
        "  --set-flags Name[,Name...]         set GEN8 InfoFlags bits (recomputes UID)\n"
        "  --clear-flags Name[,Name...]       clear GEN8 InfoFlags bits (recomputes UID)\n"
        "    flag names: Fullscreen SyncVertex1 SyncVertex2 Interpolate Scale\n"
        "                ShowCursor Sizeable ScreenKey SyncVertex3 BorderlessWindow\n",
        prog);
}

/* -------------------------------------------------------------------------
 * GEN8 InfoFlags toggle + GMS2RandomUID recompute.
 *
 * Mirror of tools/toggleflags.py: when the Info field changes, the random
 * UID checksum stored elsewhere in GEN8 has to be recomputed because Info
 * is XORed into the hash. Failing to update it causes UTMT to refuse the
 * file ("Unexpected random UID info") and the GMS2 runtime to abort.
 * ------------------------------------------------------------------------- */

struct info_flag { const char *name; uint32_t value; };
static const info_flag INFO_FLAGS[] = {
    {"Fullscreen",       0x00001},
    {"SyncVertex1",      0x00002},
    {"SyncVertex2",      0x00004},
    {"Interpolate",      0x00008},
    {"Scale",            0x00010},
    {"ShowCursor",       0x00020},
    {"Sizeable",         0x00040},
    {"ScreenKey",        0x00080},
    {"SyncVertex3",      0x00100},
    {"BorderlessWindow", 0x04000},
};

static uint32_t parse_flag_list(const char *s) {
    if (!s) return 0;
    uint32_t out = 0;
    while (*s) {
        const char *end = strchr(s, ',');
        size_t len = end ? (size_t)(end - s) : strlen(s);
        bool matched = false;
        for (const auto &f : INFO_FLAGS) {
            if (strlen(f.name) == len && strncmp(s, f.name, len) == 0) {
                out |= f.value;
                matched = true;
                break;
            }
        }
        if (!matched) {
            fprintf(stderr, "Unknown InfoFlag '%.*s'\n", (int)len, s);
            return UINT32_MAX;
        }
        s = end ? end + 1 : s + len;
    }
    return out;
}

static inline uint32_t u32le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline uint64_t u64le(const uint8_t *p) {
    return (uint64_t)u32le(p) | ((uint64_t)u32le(p + 4) << 32);
}

static uint64_t get_info_number(uint64_t first_random, bool info_ts_offset,
                                 uint64_t timestamp, uint32_t game_id,
                                 uint32_t default_w, uint32_t default_h,
                                 uint32_t info, uint32_t bytecode_version)
{
    uint64_t n = timestamp;
    if (info_ts_offset) n -= 1000;
    uint64_t t = n;
    t = ((t << 56) & 0xFF00000000000000ULL) |
        ((t >>  8) & 0x00FF000000000000ULL) |
        ((t << 32) & 0x0000FF0000000000ULL) |
        ((t >> 16) & 0x000000FF00000000ULL) |
        ((t <<  8) & 0x00000000FF000000ULL) |
        ((t >> 24) & 0x0000000000FF0000ULL) |
        ((t >> 16) & 0x000000000000FF00ULL) |
        ((t >> 32) & 0x00000000000000FFULL);
    n = t;
    n ^= first_random;
    n = ~n;
    n ^= ((uint64_t)game_id << 32) | game_id;
    uint64_t wi = (uint64_t)(default_w + info);
    uint64_t hi = (uint64_t)(default_h + info);
    n ^= (wi << 48) | (hi << 32) | (hi << 16) | wi;
    n ^= bytecode_version;
    return n;
}

static int toggle_flags_and_uid_in_file(const char *path,
                                         uint32_t set_mask, uint32_t clear_mask)
{
    FILE *f = fopen(path, "r+b");
    if (!f) { perror(path); return -1; }

    /* GEN8 is always the first chunk; an 8KB read covers it and the
     * RoomOrder / random-UID slot table that follows. */
    uint8_t hdr[8192];
    size_t nread = fread(hdr, 1, sizeof(hdr), f);
    if (nread < 0x100) {
        fprintf(stderr, "data.win too small to contain GEN8\n");
        fclose(f); return -1;
    }

    size_t gen8_start, gen8_size;
    if (find_chunk(hdr, nread, "GEN8", &gen8_start, &gen8_size) != 0) {
        fprintf(stderr, "No GEN8 chunk in first 8KB; data.win malformed\n");
        fclose(f); return -1;
    }

    uint8_t *g = hdr + gen8_start;
    uint8_t  bytecode_version = g[1];
    uint32_t game_id   = u32le(g + 0x14);
    uint32_t default_w = u32le(g + 0x3C);
    uint32_t default_h = u32le(g + 0x40);
    uint32_t old_info  = u32le(g + 0x44);
    uint64_t timestamp = u64le(g + 0x5C);
    size_t   room_off  = (bytecode_version >= 14) ? 0x80 : 0x7C;
    uint32_t room_count = u32le(g + room_off);

    uint32_t new_info = (old_info | set_mask) & ~clear_mask;
    if (new_info == old_info) {
        printf("[INFO] InfoFlags unchanged (0x%08x)\n", old_info);
        fclose(f); return 0;
    }

    size_t uid_off  = gen8_start + room_off + 4 + (size_t)room_count * 4;
    size_t need_end = uid_off + 8 + 4 * 8;  /* first_random + 4 slots */
    if (need_end > nread) {
        fprintf(stderr,
                "GEN8 UID table at offset 0x%zx extends past 8KB read window\n",
                uid_off);
        fclose(f); return -1;
    }

    uint64_t first_random = u64le(hdr + uid_off);

    long a   = (long)((timestamp & 0xFFFF) / 7);
    long b   = (long)(int32_t)(game_id - default_w);
    long sum = a + b + (long)room_count;
    long loc = (sum < 0 ? -sum : sum) % 4;
    size_t slot_off = uid_off + 8 + (size_t)loc * 8;
    uint64_t stored = u64le(hdr + slot_off);

    uint64_t expected_true  = get_info_number(first_random, true,  timestamp,
                                               game_id, default_w, default_h,
                                               old_info, bytecode_version);
    uint64_t expected_false = get_info_number(first_random, false, timestamp,
                                               game_id, default_w, default_h,
                                               old_info, bytecode_version);
    bool info_ts_offset;
    if (stored == expected_true)       info_ts_offset = true;
    else if (stored == expected_false) info_ts_offset = false;
    else {
        fprintf(stderr,
                "GMS2RandomUID didn't match either expected value for old Info; "
                "data.win may have been edited externally.\n");
        fclose(f); return -1;
    }

    uint64_t new_uid = get_info_number(first_random, info_ts_offset, timestamp,
                                        game_id, default_w, default_h,
                                        new_info, bytecode_version);

    uint8_t info_buf[4] = {
        (uint8_t)(new_info & 0xFF),
        (uint8_t)((new_info >> 8) & 0xFF),
        (uint8_t)((new_info >> 16) & 0xFF),
        (uint8_t)((new_info >> 24) & 0xFF),
    };
    uint8_t uid_buf[8];
    for (int i = 0; i < 8; i++) uid_buf[i] = (uint8_t)((new_uid >> (8 * i)) & 0xFF);

    if (fseek(f, (long)(gen8_start + 0x44), SEEK_SET) != 0
            || fwrite(info_buf, 1, 4, f) != 4
            || fseek(f, (long)slot_off, SEEK_SET) != 0
            || fwrite(uid_buf, 1, 8, f) != 8) {
        perror("write InfoFlags/UID");
        fclose(f); return -1;
    }
    fflush(f);
    fclose(f);

    printf("[INFO] InfoFlags BEFORE: 0x%08x\n", old_info);
    printf("[INFO] InfoFlags AFTER : 0x%08x\n", new_info);
    printf("[INFO] GMS2RandomUID slot %ld recomputed\n", loc);
    return 0;
}


int main(int argc, char **argv) {
    const char *data_win = NULL;
    const char *out_dir = NULL;
    const char *block_name = "4x4";
    const char *qual_name  = "-medium";
    size_t max_strip = 25000000;
    long threads = (long)std::thread::hardware_concurrency();
    if (threads <= 0) threads = 1;
    bool repack = false;
    int page_size = 512;
    int max_dims = 0;   /* 0 -> default to page_size */
    int max_area = 0;   /* 0 -> default to page_size * page_size */
    uint32_t set_flags = 0;
    uint32_t clear_flags = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--block") && i + 1 < argc)                 block_name = argv[++i];
        else if (!strcmp(argv[i], "--quality") && i + 1 < argc)          qual_name  = argv[++i];
        else if (!strcmp(argv[i], "--max-strip-pixels") && i + 1 < argc) max_strip  = strtoull(argv[++i], NULL, 10);
        else if (!strcmp(argv[i], "--threads") && i + 1 < argc) {
            threads = strtol(argv[++i], NULL, 10);
            if (threads < 1) threads = 1;
        }
        else if (!strcmp(argv[i], "--repack"))                           repack = true;
        else if (!strcmp(argv[i], "--page-size") && i + 1 < argc) {
            page_size = (int)strtol(argv[++i], NULL, 10);
            if (page_size < 64) page_size = 64;
        }
        else if (!strcmp(argv[i], "--max-dims") && i + 1 < argc) {
            max_dims = (int)strtol(argv[++i], NULL, 10);
            if (max_dims < 1) max_dims = 1;
        }
        else if (!strcmp(argv[i], "--max-area") && i + 1 < argc) {
            max_area = (int)strtol(argv[++i], NULL, 10);
            if (max_area < 1) max_area = 1;
        }
        else if (!strcmp(argv[i], "--set-flags") && i + 1 < argc) {
            set_flags = parse_flag_list(argv[++i]);
            if (set_flags == UINT32_MAX) return 2;
        }
        else if (!strcmp(argv[i], "--clear-flags") && i + 1 < argc) {
            clear_flags = parse_flag_list(argv[++i]);
            if (clear_flags == UINT32_MAX) return 2;
        }
        else if (argv[i][0] != '-') {
            if (!data_win)      data_win = argv[i];
            else if (!out_dir)  out_dir  = argv[i];
            else { usage(argv[0]); return 2; }
        }
        else { usage(argv[0]); return 2; }
    }
    if (!data_win || !out_dir) { usage(argv[0]); return 2; }

    const struct block_info *blk = find_block(block_name);
    if (!blk) { fprintf(stderr, "Unknown --block: %s\n", block_name); return 2; }
    float quality;
    if (parse_quality(qual_name, &quality) != 0) {
        fprintf(stderr, "Unknown --quality: %s\n", qual_name); return 2;
    }
    if (portable_mkdir(out_dir) != 0) {
        perror(out_dir); return 3;
    }

    if (repack) {
        int r = run_repack(data_win, out_dir, blk, quality, max_strip,
                           (unsigned)threads, page_size, max_dims, max_area);
        if (r != 0) return r;
        if (set_flags || clear_flags) {
            if (toggle_flags_and_uid_in_file(data_win, set_flags, clear_flags) != 0)
                return 9;
        }
        return 0;
    }

    FILE *f = fopen(data_win, "r+b");
    if (!f) { perror(data_win); return 3; }
    fseek(f, 0, SEEK_END);
    long total_size = ftell(f);
    rewind(f);
    if (total_size <= 0) { fprintf(stderr, "Empty data.win\n"); fclose(f); return 3; }

    uint8_t *win = (uint8_t *)malloc((size_t)total_size);
    if (!win) { fprintf(stderr, "OOM reading data.win\n"); fclose(f); return 4; }
    if (fread(win, 1, (size_t)total_size, f) != (size_t)total_size) {
        fprintf(stderr, "short read on %s\n", data_win);
        free(win); fclose(f); return 4;
    }

    size_t txtr_start, txtr_size;
    if (find_txtr(win, (size_t)total_size, &txtr_start, &txtr_size) != 0) {
        fprintf(stderr, "No TXTR chunk in %s\n", data_win);
        free(win); fclose(f); return 5;
    }
    printf("TXTR chunk: offset=0x%zx  size=%zu (%.1f MB)\n",
           txtr_start, txtr_size, txtr_size / 1048576.0);
    fflush(stdout);

    size_t txtr_end = txtr_start + txtr_size;
    size_t scan_from = txtr_start;
    unsigned int n_textures = 0;
    unsigned int cap = 64;
    uint8_t **stubs = (uint8_t **)malloc(cap * sizeof(uint8_t *));
    size_t *stub_lens = (size_t *)malloc(cap * sizeof(size_t));
    if (!stubs || !stub_lens) {
        fprintf(stderr, "OOM\n");
        free(stubs); free(stub_lens); free(win); fclose(f); return 4;
    }

    /* One astcenc context for all blobs in the legacy single-pass mode. */
    astcenc_context *astc_ctx = astc_make_context(blk->bx, blk->by,
                                                   quality, (unsigned)threads);
    if (!astc_ctx) {
        free(stubs); free(stub_lens); free(win); fclose(f); return 4;
    }

    char pvr_path[1024];
    while (scan_from < txtr_end) {
        size_t off = find_next_zoq(win, scan_from, txtr_end);
        if (off == (size_t)-1) break;
        size_t blob_len = scan_2zoq_blob_len(win + off, txtr_end - off);
        if (blob_len == 0) { scan_from = off + 1; continue; }

        int tex_w = win[off+4] | (win[off+5] << 8);
        int tex_h = win[off+6] | (win[off+7] << 8);
        printf("Texture %u (%dx%d): compressing...\n", n_textures, tex_w, tex_h);
        fflush(stdout);

        snprintf(pvr_path, sizeof(pvr_path), "%s/%u.pvr", out_dir, n_textures);
        if (compress_blob_to_pvr(win + off, blob_len, pvr_path,
                                  blk, astc_ctx, (unsigned)threads, max_strip) != 0) {
            astcenc_context_free(astc_ctx);
            free(stubs); free(stub_lens); free(win); fclose(f); return 6;
        }

        if (n_textures == cap) {
            cap *= 2;
            stubs = (uint8_t **)realloc(stubs, cap * sizeof(uint8_t *));
            stub_lens = (size_t *)realloc(stub_lens, cap * sizeof(size_t));
            if (!stubs || !stub_lens) {
                fprintf(stderr, "OOM growing stub list\n");
                free(win); fclose(f); return 4;
            }
        }
        if (build_2zoq_stub(n_textures, &stubs[n_textures], &stub_lens[n_textures]) != 0) {
            fprintf(stderr, "build_2zoq_stub %u failed\n", n_textures);
            astcenc_context_free(astc_ctx);
            free(stubs); free(stub_lens); free(win); fclose(f); return 7;
        }

        n_textures++;
        scan_from = off + blob_len;
    }
    astcenc_context_free(astc_ctx);
    free(win);
    printf("Found %u 2zoq textures.\n", n_textures);
    fflush(stdout);

    long new_size = compact_txtr(f, txtr_start, txtr_size, stubs, stub_lens, n_textures);
    for (unsigned int i = 0; i < n_textures; i++) free(stubs[i]);
    free(stubs);
    free(stub_lens);
    if (new_size == 0) { fclose(f); return 8; }
    fclose(f);

    printf("Updated %s: %ld -> %ld (%.1f MB saved)\n",
           data_win, total_size, new_size,
           (total_size - new_size) / 1048576.0);

    if (set_flags || clear_flags) {
        if (toggle_flags_and_uid_in_file(data_win, set_flags, clear_flags) != 0)
            return 9;
    }
    return 0;
}
