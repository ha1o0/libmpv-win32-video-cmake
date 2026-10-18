"""Apply the recipe patches to a copy and test their actual C policy functions.

Needs CMake, a C11 compiler and libcurl development files. On Windows pass a
static curl install as --curl-prefix. Does not build mpv or modify its checkout.
"""
import argparse
import collections
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time


def run(args, cwd=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                            encoding="utf8", errors="replace", timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def definition(source, pattern, semicolon=False):
    match = re.search(pattern, source)
    assert match, pattern
    brace = source.index("{", match.start())
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if semicolon:
        assert source[end] == ";"
        end += 1
    return source[match.start():end] + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mpv-source", type=Path, required=True)
    parser.add_argument("--curl-prefix", type=Path)
    parser.add_argument("--cmake", default="cmake")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    # Keep artifacts outside the supplied checkout; it is read only.
    artifacts = repo / "build-curl-validation"
    artifacts.mkdir(exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="curl-policy-", dir=artifacts))
    source_dir = scratch / "source"
    (source_dir / "stream").mkdir(parents=True)
    original = (args.mpv_source / "stream/stream_curl.c").read_bytes()
    (source_dir / "stream/stream_curl.c").write_bytes(original)
    git = ["git", "-c", "user.name=Policy test", "-c",
           "user.email=policy@example.invalid"]
    run(git + ["init", "--quiet"], source_dir)
    run(git + ["add", "stream/stream_curl.c"], source_dir)
    run(git + ["commit", "--quiet", "-m", "zcopy source fixture"], source_dir)
    patches = sorted((repo / "packages").glob("mpv-*.patch"))
    run(git + ["am", "--3way", *map(str, patches)], source_dir)
    source = (source_dir / "stream/stream_curl.c").read_text(encoding="utf8")
    types = ""
    for name, kind in [("curl_proto", "enum"), ("curl_scheme", "struct"),
                       ("curl_opts", "struct"), ("curl_ctx", "struct"),
                       ("priv", "struct"), ("cmd_kind", "enum"), ("cmd", "struct")]:
        types += definition(source, rf"(?m)^{kind} {name} \{{", True)
    (scratch / "policy_types.inc").write_text(types, encoding="utf8")
    functions = ""
    for name in ["cancel_retry", "retry_request", "process_retries", "run_cmd",
                 "is_http_success", "ring_write", "write_callback", "xferinfo_callback",
                 "parse_content_range_total", "header_value", "finalize_probe",
                 "probe_http", "probe_ftp", "header_callback",
                 "is_recoverable_error", "start_request", "on_done"]:
        body = definition(source, rf"(?m)^static [\w *]+\b{name}\([^;]*?\)\n\{{")
        if name == "start_request":
            body = body.replace("start_request(", "start_request_native(", 1)
        functions += body
    (scratch / "policy_functions.inc").write_text(functions, encoding="utf8")
    # Check the production wiring omitted by the tiny harness probe/dispatcher.
    assert "p->last_activity = mp_time_sec();" in definition(source, r"(?m)^static size_t header_callback\(")
    assert "if (p->probed) {\n        p->stream_ok = true;\n        return;" in source
    assert "MPMIN(connect_timeout, p->net_opts->timeout)" in source
    assert "cancel_retry(c->p);" in source
    cmake = """cmake_minimum_required(VERSION 3.21)
project(curl_policy_test C)
set(CMAKE_C_STANDARD 11)
set(CURL_USE_STATIC_LIBS ON)
find_package(CURL REQUIRED)
add_executable(policy_test curl_network_policy.c)
target_include_directories(policy_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(policy_test PRIVATE CURL::libcurl)
if(MSVC)
 target_compile_options(policy_test PRIVATE /experimental:c11atomics)
endif()
if(WIN32)
 target_link_libraries(policy_test PRIVATE wldap32 normaliz bcrypt advapi32 crypt32 secur32 ws2_32 iphlpapi)
endif()
"""
    (scratch / "CMakeLists.txt").write_text(cmake, encoding="utf8")
    shutil.copy2(repo / "tests/curl_network_policy.c", scratch)
    configure = [args.cmake, "-S", str(scratch), "-B", str(scratch / "build")]
    if args.curl_prefix:
        configure += ["-DCMAKE_PREFIX_PATH=" + str(args.curl_prefix.resolve())]
    run(configure)
    run([args.cmake, "--build", str(scratch / "build"), "--config", "Release"])
    binary = scratch / "build" / ("Release/policy_test.exe" if os.name == "nt" else "policy_test")
    print(run([str(binary)]).strip(), flush=True)
    requests = collections.defaultdict(list)

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *unused):
            pass

        def do_GET(self):
            mode = self.path.strip("/")
            requests[mode].append(self.headers.get("Range"))
            attempt = len(requests[mode])
            try:
                if mode == "redirect":
                    self.send_response(302)
                    self.send_header("Location", "/destination")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if mode == "forbidden" or (mode == "reject" and attempt > 1):
                    self.send_response(403)
                    self.send_header("Content-Length", "32")
                    self.end_headers()
                    self.wfile.write(b"x" * 32)
                    self.wfile.flush()
                    return
                if mode == "headers":
                    time.sleep(5)
                    return
                start = int((self.headers.get("Range") or "bytes=0-").split("=")[1].split("-")[0])
                size = 262144 if mode == "pause" else 96
                self.send_response(200 if mode == "streamed" else 206)
                if mode != "streamed":
                    self.send_header("Accept-Ranges", "bytes")
                    self.send_header("Content-Range", f"bytes {start}-{size-1}/{size}")
                self.send_header("Content-Length", str(size - start))
                self.end_headers()
                if mode in ["stall", "cancel"]:
                    self.wfile.write(b"a" * 32)
                    self.wfile.flush()
                    time.sleep(5)
                elif mode in ["recover", "streamed"] and attempt == 1:
                    self.wfile.write(b"a" * 32)
                    self.wfile.flush()
                    self.close_connection = True
                    self.connection.shutdown(socket.SHUT_RDWR)
                elif mode == "reject" and attempt == 1:
                    self.wfile.write(b"a" * 32)
                    self.wfile.flush()
                    self.close_connection = True
                else:
                    self.wfile.write(b"b" * (size - start))
                    self.wfile.flush()
            except (OSError, BrokenPipeError):
                pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    results = {}
    try:
        for mode in ["recover", "streamed", "stall", "headers", "pause", "cancel",
                     "reject", "forbidden", "redirect"]:
            url = f"http://127.0.0.1:{server.server_port}/{mode}"
            result = json.loads(run([str(binary), url, mode]))
            result["ranges"] = requests[mode]
            results[mode] = result
            if mode == "recover":
                assert result["bytes"] == 96 and not result["error"], result
                assert result["ranges"] == ["bytes=0-", "bytes=32-"], result
            elif mode == "streamed":
                assert result["bytes"] == 128 and not result["error"], result
                assert result["ranges"] == ["bytes=0-", None], result
            elif mode in ["stall", "headers"]:
                assert result["error"] and result["attempts"] == 2 and result["elapsed"] < 9, result
            elif mode == "pause":
                assert not result["error"] and result["attempts"] == 1 and result["pauses"] > 0, result
                assert result["bytes"] == 262144 and result["elapsed"] >= 3, result
            elif mode == "cancel":
                assert result["cancelled"] and result["attempts"] == 1 and result["elapsed"] < 3, result
            elif mode == "reject":
                assert result["error"] and result["attempts"] == 2 and result["bytes"] == 32, result
            elif mode == "forbidden":
                assert result["error"] and result["attempts"] == 1 and result["bytes"] == 0, result
            elif mode == "redirect":
                assert not result["error"] and result["attempts"] == 1 and result["bytes"] == 96, result
            print(mode + ": " + json.dumps(result), flush=True)
    finally:
        server.shutdown()
        server.server_close()
    assert (args.mpv_source / "stream/stream_curl.c").read_bytes() == original
    (scratch / "results.json").write_text(json.dumps(results, indent=2), encoding="utf8")
    print("Passed; artifacts: " + str(scratch), flush=True)


if __name__ == "__main__":
    main()
