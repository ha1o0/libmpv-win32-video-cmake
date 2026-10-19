#include <curl/curl.h>

// This DLL is a build check only; it is neither run nor shipped with mpv.
// These entry points pull the transport and TLS dependency graph into the link.
__declspec(dllexport) int curl_static_link_check(void)
{
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
        return 1;
    CURL *easy = curl_easy_init();
    CURLM *multi = curl_multi_init();
    int result = 1;
    if (easy && multi) {
        curl_easy_setopt(easy, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_2TLS);
        curl_multi_add_handle(multi, easy);
        curl_multi_remove_handle(multi, easy);
        const curl_version_info_data *version = curl_version_info(CURLVERSION_NOW);
        const int required = CURL_VERSION_HTTP2 | CURL_VERSION_HTTP3 | CURL_VERSION_SSL;
        result = !version || (version->features & required) != required;
    }
    if (multi)
        curl_multi_cleanup(multi);
    if (easy)
        curl_easy_cleanup(easy);
    curl_global_cleanup();
    return result;
}
