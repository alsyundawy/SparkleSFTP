#include "Clibcurl.h"
#include <pthread.h>

static pthread_once_t g_curl_init_once = PTHREAD_ONCE_INIT;

static void sparklesftp_do_global_init(void) {
    curl_global_init(CURL_GLOBAL_DEFAULT);
}

void sparklesftp_curl_global_init_once(void) {
    pthread_once(&g_curl_init_once, sparklesftp_do_global_init);
}

CURLcode sparklesftp_curl_setopt_long(CURL *handle, CURLoption option, long value) {
    return curl_easy_setopt(handle, option, value);
}

CURLcode sparklesftp_curl_setopt_off_t(CURL *handle, CURLoption option, curl_off_t value) {
    return curl_easy_setopt(handle, option, value);
}

CURLcode sparklesftp_curl_setopt_string(CURL *handle, CURLoption option, const char *value) {
    return curl_easy_setopt(handle, option, value);
}

CURLcode sparklesftp_curl_setopt_pointer(CURL *handle, CURLoption option, const void *value) {
    return curl_easy_setopt(handle, option, value);
}

CURLcode sparklesftp_curl_setopt_slist(CURL *handle, CURLoption option, struct curl_slist *value) {
    return curl_easy_setopt(handle, option, value);
}

CURLcode sparklesftp_curl_setopt_write_cb(CURL *handle, SparkleCurlWriteCallback cb, void *userdata) {
    CURLcode res = curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, cb);
    if (res != CURLE_OK) {
        return res;
    }
    return curl_easy_setopt(handle, CURLOPT_WRITEDATA, userdata);
}

CURLcode sparklesftp_curl_setopt_read_cb(CURL *handle, SparkleCurlReadCallback cb, void *userdata) {
    CURLcode res = curl_easy_setopt(handle, CURLOPT_READFUNCTION, cb);
    if (res != CURLE_OK) {
        return res;
    }
    return curl_easy_setopt(handle, CURLOPT_READDATA, userdata);
}

CURLcode sparklesftp_curl_setopt_xfer_cb(CURL *handle, SparkleCurlXferInfoCallback cb, void *userdata) {
    CURLcode res = curl_easy_setopt(handle, CURLOPT_NOPROGRESS, 0L);
    if (res != CURLE_OK) {
        return res;
    }
    res = curl_easy_setopt(handle, CURLOPT_XFERINFOFUNCTION, cb);
    if (res != CURLE_OK) {
        return res;
    }
    return curl_easy_setopt(handle, CURLOPT_XFERINFODATA, userdata);
}

CURLcode sparklesftp_curl_getinfo_long(CURL *handle, CURLINFO info, long *out_value) {
    return curl_easy_getinfo(handle, info, out_value);
}

CURLcode sparklesftp_curl_getinfo_off_t(CURL *handle, CURLINFO info, curl_off_t *out_value) {
    return curl_easy_getinfo(handle, info, out_value);
}
