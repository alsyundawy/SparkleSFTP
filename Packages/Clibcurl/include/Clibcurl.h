#ifndef CLIBCURL_HELPERS_H
#define CLIBCURL_HELPERS_H

#include <curl/curl.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef size_t (*SparkleCurlWriteCallback)(char *ptr, size_t size, size_t nmemb, void *userdata);
typedef size_t (*SparkleCurlReadCallback)(char *buffer, size_t size, size_t nitems, void *userdata);
typedef int (*SparkleCurlXferInfoCallback)(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal,
                                           curl_off_t ulnow);

void sparklesftp_curl_global_init_once(void);

CURLcode sparklesftp_curl_setopt_long(CURL *handle, CURLoption option, long value);
CURLcode sparklesftp_curl_setopt_off_t(CURL *handle, CURLoption option, curl_off_t value);
CURLcode sparklesftp_curl_setopt_string(CURL *handle, CURLoption option, const char *value);
CURLcode sparklesftp_curl_setopt_pointer(CURL *handle, CURLoption option, const void *value);
CURLcode sparklesftp_curl_setopt_slist(CURL *handle, CURLoption option, struct curl_slist *value);
CURLcode sparklesftp_curl_setopt_write_cb(CURL *handle, SparkleCurlWriteCallback cb, void *userdata);
CURLcode sparklesftp_curl_setopt_read_cb(CURL *handle, SparkleCurlReadCallback cb, void *userdata);
CURLcode sparklesftp_curl_setopt_xfer_cb(CURL *handle, SparkleCurlXferInfoCallback cb, void *userdata);

CURLcode sparklesftp_curl_getinfo_long(CURL *handle, CURLINFO info, long *out_value);
CURLcode sparklesftp_curl_getinfo_off_t(CURL *handle, CURLINFO info, curl_off_t *out_value);

/* Third-party runtime introspection & bounded zlib codec helpers */
void sparklesftp_curl_version_summary(char *out_buffer, size_t capacity);
int sparklesftp_curl_supports_zlib(void);
void sparklesftp_zlib_version(char *out_buffer, size_t capacity);
int sparklesftp_zlib_deflate(const uint8_t *input, size_t input_len, int level, int use_gzip, uint8_t **out_data,
                             size_t *out_len);
int sparklesftp_zlib_inflate(const uint8_t *input, size_t input_len, size_t max_output_bytes, uint8_t **out_data,
                             size_t *out_len);
void sparklesftp_zlib_free(void *ptr);
int sparklesftp_probe_libssh2(char *out_version, size_t capacity, char *out_path, size_t path_capacity);

#ifdef __cplusplus
}
#endif

#endif /* CLIBCURL_HELPERS_H */
