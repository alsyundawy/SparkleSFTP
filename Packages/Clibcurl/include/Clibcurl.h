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
typedef int (*SparkleCurlXferInfoCallback)(
    void *clientp,
    curl_off_t dltotal,
    curl_off_t dlnow,
    curl_off_t ultotal,
    curl_off_t ulnow
);

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

#ifdef __cplusplus
}
#endif

#endif /* CLIBCURL_HELPERS_H */
