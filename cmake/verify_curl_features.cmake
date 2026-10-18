# Validate the installed cross-compiled library, not the host's curl executable.
cmake_minimum_required(VERSION 3.19)

if(NOT DEFINED CURL_PC OR NOT EXISTS "${CURL_PC}")
    message(FATAL_ERROR "Target libcurl.pc is missing: ${CURL_PC}")
endif()

file(STRINGS "${CURL_PC}" features REGEX "^supported_features=")
file(STRINGS "${CURL_PC}" protocols REGEX "^supported_protocols=")
file(STRINGS "${CURL_PC}" cflags REGEX "^Cflags:")
file(STRINGS "${CURL_PC}" requires REGEX "^Requires:")
string(REPLACE "\"" " " features "${features}")
string(REPLACE "\"" " " protocols "${protocols}")

foreach(feature HTTP2 SSL)
    if(NOT features MATCHES "[ =]${feature}([ ;]|$)")
        message(FATAL_ERROR "Target libcurl must support ${feature}: ${features}")
    endif()
endforeach()
if(NOT DEFINED CURL_CONFIG OR NOT EXISTS "${CURL_CONFIG}")
    message(FATAL_ERROR "Target curl-config is missing: ${CURL_CONFIG}")
endif()
# curl-config is a host shell script, even for a cross-compiled target. Schannel
# is an SSL backend, not a token in libcurl.pc's supported_features field.
find_program(BASH_EXECUTABLE NAMES bash REQUIRED)
execute_process(
    COMMAND "${BASH_EXECUTABLE}" "${CURL_CONFIG}" --ssl-backends
    RESULT_VARIABLE ssl_status
    OUTPUT_VARIABLE ssl_backends
    ERROR_VARIABLE ssl_error
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(NOT ssl_status EQUAL 0 OR NOT ssl_backends MATCHES "(^|[ ,;])Schannel([ ,;]|$)")
    message(FATAL_ERROR "Target libcurl must use Schannel: ${ssl_backends} ${ssl_error}")
endif()
foreach(protocol HTTP HTTPS)
    if(NOT protocols MATCHES "[ =]${protocol}([ ;]|$)")
        message(FATAL_ERROR "Target libcurl must support ${protocol}: ${protocols}")
    endif()
endforeach()
if(NOT cflags MATCHES "(^|[ ])-DCURL_STATICLIB([ ]|$)")
    message(FATAL_ERROR "Target libcurl must publish static-link Cflags: ${cflags}")
endif()
if(NOT requires MATCHES "(^|[ :,])libnghttp2([ ,<>=]|$)")
    message(FATAL_ERROR "Target libcurl must publish its static nghttp2 dependency: ${requires}")
endif()

message(STATUS "Verified target libcurl: static, HTTP/HTTPS, HTTP2, Schannel")
