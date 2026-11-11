#include "Clibcurl.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

void sparklesftp_curl_version_summary(char *out_buffer, size_t capacity) {
    if (out_buffer == NULL || capacity == 0) {
        return;
    }
    const curl_version_info_data *info = curl_version_info(CURLVERSION_NOW);
    if (info == NULL) {
        out_buffer[0] = '\0';
        return;
    }
    const char *ssl = info->ssl_version != NULL ? info->ssl_version : "none";
    const char *libz = info->libz_version != NULL ? info->libz_version : "none";
    const char *ssh = info->libssh_version != NULL ? info->libssh_version : "none";
    (void)snprintf(out_buffer, capacity, "libcurl/%s (SSL: %s, zlib: %s, SSH: %s)", info->version, ssl, libz, ssh);
}

int sparklesftp_curl_supports_zlib(void) {
    const curl_version_info_data *info = curl_version_info(CURLVERSION_NOW);
    if (info == NULL) {
        return 0;
    }
    return (info->features & CURL_VERSION_LIBZ) != 0 ? 1 : 0;
}

void sparklesftp_zlib_version(char *out_buffer, size_t capacity) {
    if (out_buffer == NULL || capacity == 0) {
        return;
    }
    (void)snprintf(out_buffer, capacity, "%s", zlibVersion());
}

int sparklesftp_zlib_deflate(const uint8_t *input, size_t input_len, int level, int use_gzip, uint8_t **out_data,
                             size_t *out_len) {
    if (out_data == NULL || out_len == NULL) {
        return -1;
    }
    *out_data = NULL;
    *out_len = 0;

    if ((input == NULL && input_len > 0) || input_len > (size_t)UINT32_MAX) {
        return -1;
    }
    if (level < Z_NO_COMPRESSION || level > Z_BEST_COMPRESSION) {
        level = Z_DEFAULT_COMPRESSION;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    int window_bits = use_gzip ? (MAX_WBITS + 16) : MAX_WBITS;
    if (deflateInit2(&stream, level, Z_DEFLATED, window_bits, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return -2;
    }

    uLong bound = deflateBound(&stream, (uLong)input_len);
    if (bound > (uLong)UINT32_MAX) {
        deflateEnd(&stream);
        return -1;
    }
    if (bound == 0) {
        bound = 16;
    }
    uint8_t *buffer = (uint8_t *)malloc((size_t)bound);
    if (buffer == NULL) {
        deflateEnd(&stream);
        return -3;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;
    stream.next_out = (Bytef *)buffer;
    stream.avail_out = (uInt)bound;

    int status = deflate(&stream, Z_FINISH);
    if (status != Z_STREAM_END) {
        free(buffer);
        deflateEnd(&stream);
        return -4;
    }

    *out_data = buffer;
    *out_len = (size_t)stream.total_out;
    deflateEnd(&stream);
    return 0;
}

int sparklesftp_zlib_inflate(const uint8_t *input, size_t input_len, size_t max_output_bytes, uint8_t **out_data,
                             size_t *out_len) {
    if (out_data == NULL || out_len == NULL || max_output_bytes == 0) {
        return -1;
    }
    *out_data = NULL;
    *out_len = 0;
    if (input == NULL || input_len == 0 || input_len > (size_t)UINT32_MAX || max_output_bytes > (size_t)UINT32_MAX) {
        return -1;
    }

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, MAX_WBITS + 32) != Z_OK) {
        return -2;
    }

    size_t capacity = input_len < 1024 ? 4096 : (input_len * 4);
    if (capacity > max_output_bytes) {
        capacity = max_output_bytes;
    }
    uint8_t *buffer = (uint8_t *)malloc(capacity);
    if (buffer == NULL) {
        inflateEnd(&stream);
        return -3;
    }

    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_len;

    for (;;) {
        if (stream.total_out >= max_output_bytes) {
            if (stream.avail_in > 0) {
                uint8_t trailer_probe = 0;
                stream.next_out = (Bytef *)&trailer_probe;
                stream.avail_out = 0;
                int probe_status = inflate(&stream, Z_NO_FLUSH);
                if (probe_status == Z_STREAM_END) {
                    *out_data = buffer;
                    *out_len = (size_t)stream.total_out;
                    inflateEnd(&stream);
                    return 0;
                }
            }
            free(buffer);
            inflateEnd(&stream);
            return -5;
        }
        size_t remaining_cap = capacity - (size_t)stream.total_out;
        if (remaining_cap == 0) {
            size_t next_cap = capacity <= (max_output_bytes / 2) ? (capacity * 2) : max_output_bytes;
            if (next_cap <= capacity) {
                free(buffer);
                inflateEnd(&stream);
                return -5;
            }
            uint8_t *grown = (uint8_t *)realloc(buffer, next_cap);
            if (grown == NULL) {
                free(buffer);
                inflateEnd(&stream);
                return -3;
            }
            buffer = grown;
            capacity = next_cap;
            remaining_cap = capacity - (size_t)stream.total_out;
        }

        stream.next_out = (Bytef *)(buffer + stream.total_out);
        stream.avail_out = (uInt)remaining_cap;

        int status = inflate(&stream, Z_NO_FLUSH);
        if (status == Z_STREAM_END) {
            *out_data = buffer;
            *out_len = (size_t)stream.total_out;
            inflateEnd(&stream);
            return 0;
        }
        if (status != Z_OK && status != Z_BUF_ERROR) {
            free(buffer);
            inflateEnd(&stream);
            return -4;
        }
        if (stream.avail_in == 0 && stream.avail_out > 0) {
            free(buffer);
            inflateEnd(&stream);
            return -4;
        }
    }
}

void sparklesftp_zlib_free(void *ptr) {
    free(ptr);
}

typedef const char *(*SparkleLibssh2VersionFn)(int required_version);

int sparklesftp_probe_libssh2(char *out_version, size_t capacity, char *out_path, size_t path_capacity) {
    if (out_version == NULL || capacity == 0) {
        return 0;
    }
    out_version[0] = '\0';
    if (out_path != NULL && path_capacity > 0) {
        out_path[0] = '\0';
    }

    static const char *const kCandidatePaths[] = {
        "/opt/homebrew/opt/libssh2/lib/libssh2.1.dylib",
        "/usr/local/opt/libssh2/lib/libssh2.1.dylib",
        "/opt/homebrew/lib/libssh2.1.dylib",
        "/usr/local/lib/libssh2.1.dylib",
    };

    const size_t count = sizeof(kCandidatePaths) / sizeof(kCandidatePaths[0]);
    for (size_t i = 0; i < count; i++) {
        void *handle = dlopen(kCandidatePaths[i], RTLD_LAZY | RTLD_LOCAL);
        if (handle == NULL) {
            continue;
        }
        const void *sym = dlsym(handle, "libssh2_version");
        SparkleLibssh2VersionFn version_fn = NULL;
        memcpy(&version_fn, &sym, sizeof(version_fn));
        if (version_fn != NULL) {
            const char *ver = version_fn(0);
            if (ver != NULL) {
                (void)snprintf(out_version, capacity, "%s", ver);
                if (out_path != NULL && path_capacity > 0) {
                    (void)snprintf(out_path, path_capacity, "%s", kCandidatePaths[i]);
                }
                dlclose(handle);
                return 1;
            }
        }
        dlclose(handle);
    }
    return 0;
}
