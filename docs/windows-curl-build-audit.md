# Windows curl 构建审查（2026-10-19）

目标：为 `ha1o0/mpv:zcopy` 的 Windows libmpv 编入静态 libcurl 和 HTTP/2，
再通过相同视频地址的播放测试验证加载速度。当前分支同时保留已加入的 HTTP/3、
QUIC、ECH 等能力。HTTP/2 编译成功和播放加载变快是两个需要分别验证的结论。

## 审查基线

- 本地分支：`zc`，审查起点 `a5f1c145a512892b0a4625de12aebeedbe0573a0`。
- 近期改动之前的基线：`aa84ce7`。
- 已实际 fetch 的上游：`shinchiro/mpv-winbuild-cmake` 的
  `1f8d2e76255abc48f0456d9be99b4cab9c6566e6`。
- mpv 源码：`ha1o0/mpv:zcopy` 的 `f21c602c3b379734c8bb5ccdc437e52514d2288c`。
- 三次 CI：`39180781573`（libvpl）、`39183585164`（libplacebo）、
  `39185469894`（libbluray）。分析包括每次单独上传的编译日志产物。

## 昨天以来的提交实际做了什么

| 提交 | 实际范围 | 与目标的关系及审查结论 |
| --- | --- | --- |
| `aa7a0d2`，10 月 18 日 21:42 | 为 mpv 增加 curl 依赖和 `libcurl=enabled`；curl 从原 mbedTLS/autotools 方案切到 CMake、OpenSSL、nghttp2 静态构建；加入特性校验 | 这是引入 HTTP/2 的核心改动；只打开 mpv 开关不够，必须同时编出支持 HTTP/2 的目标 libcurl |
| `9748b91`，10 月 18 日 22:06 | 加入 nghttp3、ngtcp2、c-ares、libpsl；固定网络依赖快照；开启 QUIC/ECH、HTTP/3 及 DNS 等特性；加入 libssh SCP 头文件补丁 | 功能范围扩展到了 HTTP/3；HTTP/2 本身不要求这些额外能力，但本次修复保留它们；独立固定的 curl/OpenSSL 快照存在实际 API 不匹配，见下文 |
| `b5ee052`，10 月 19 日 07:47 | 重定位 Vulkan 静态链接补丁；初始化 PSL 子模块；OpenSSL 缓存重配置；加入 mpv 代理路由、超时、重连及延迟重试补丁和测试 | 标题只提 Vulkan，实际混合了构建和运行时改动；两个 mpv 补丁关系到应用代理及网络策略，不能视为单纯编译开关 |
| `a5f1c14`，10 月 19 日 09:03 | 限定 libvpl 旧 MSVC 兼容宏；在 libplacebo 配置/编译/安装前恢复 glad 和 fast_float 软链接 | 前两次构建的具体阻塞已被修复；但 libplacebo 修复仅覆盖一个依赖，没有修复公共缓存机制 |

## 与上游对比

上游已使用静态 curl、OpenSSL、nghttp2/nghttp3/ngtcp2、c-ares、libpsl、libssh 和
压缩库，并将 curl 列为 mpv 依赖。本分支的依赖方向与上游一致。上游
`05a60b3` 对 libvpl 的修复与本分支采用的预处理条件一致。

本分支仍有应保留的差异：自定义 zcopy 内核、固定 FFmpeg、静态 Vulkan loader、
libmpv 开发产物及当前 LLVM 22 工具链。上游当前声明 LLVM 23，不能为了 curl
把这些差异整体覆盖。本次不调整渲染、硬解、HDR、FFmpeg 功能开关或编译器版本。

本地 libbluray 比上游少了两项默认文件系统函数重命名。实际检查当前 libdvdread
源码，相关实现已经是 `static`，没有据此新增无必要的重命名。

本分支的 `CURL_WINDOWS_SSPI=ON` 是固定 curl 快照中的实际 CMake 开关，予以保留。

## 连续失败的原因

### 1. libvpl：已修复的源码兼容问题

MinGW 未定义 `_MSC_VER`，原判断 `_MSC_VER < 1400` 把它按零计算，启用了会
破坏 Windows `stralign.h` 表达式的兼容宏。限制为
`defined(_MSC_VER) && _MSC_VER < 1400` 后，Windows x86_64 静态库已编译验证通过。

### 2. libplacebo 和 libbluray：同类缓存状态错误

CI 在失败后仍保存源码和构建缓存。旧公共更新脚本会执行 Git 重置，移除配置阶段
对源码的调整，却可能保留 configure/build/install 的完成标记：

- libplacebo 的 glad/fast_float 软链接被还原为空的子模块目录；重新生成构建文件
  时无法导入 glad。
- libbluray 配置阶段原本删除了 `cc.find_library('ssp')`；重置恢复了该行，缓存又
  直接进入安装，Meson 重新配置时报告目标 sysroot 没有 `ssp`。这个源码调整本身
  也存在于上游，并非 curl 新增了 SSP 依赖。

同类配置阶段操作还存在于 libdvdread、fontconfig、libpsl、libjxl、libzimg 等配方。
因此需要公共状态修复，不能只逐个修改失败的库。

### 3. 固定版本依赖的处理错误

旧脚本即使面对 detached HEAD，仍查询 `@{u}`，产生反复的 fatal 信息。
`GIT_RESET` 非空时又跳过删除阶段标记；有些声明还会因为没有显式设置
`GIT_REMOTE_NAME` 而忽略 `GIT_RESET`。这会使固定源码和旧编译产物不一致。
声明命名分支时，也应更新到已经 fetch 的远端分支，而不是仅重置到本地旧 HEAD。

### 4. 本次完整交叉编译发现的 curl/OpenSSL API 不匹配

curl 固定于 `3163ec065643ba20709f190111f42c3e1fe95273`，版本实际为 `8.23.0-DEV`；
OpenSSL 固定于 `d8bf6cdd4849925c30e4f1911c7acb49cb34b702`，声明 `4.1.0-dev`。
这个 OpenSSL 快照没有 `ASN1_STRING_get_length`，但 curl 原来只按版本号判断其
存在，导致 Windows 编译出现四处未声明函数错误。

兼容补丁用 CMake 检测实际 API，并通过私有包装函数调用新 API 或原先的旧 API
兼容转换。没有升级 OpenSSL，也没有关闭 TLS 校验、HTTP/3 或 ECH。

## 本轮修复

- 统一解析固定 SHA、tag、命名远端分支和普通跟踪分支；旧浅克隆缺少固定 SHA 时
  补取指定提交。
- 源码版本、配方或补丁改变，或 Git 重置将丢弃配置阶段修改时，同步失效所有相关
  阶段标记，让配置和源码准备重新执行。
- 初次迁移时，所有缺少 `RECIPE` 指纹的旧 Git 依赖缓存均重建一次，包括已经完成
  的缓存；旧完成标记无法证明产物使用了当前配方和补丁。之后复用指纹和源码匹配
  的已完成缓存。
- 成功安装后的清理单独处理，保留完成标记和已经应用的补丁提交，避免无休止重编。
- 补丁阶段重新执行前先恢复请求的源码基线，避免缓存中的补丁被重复应用。
- nghttp3 配置前同步 sfparse 子模块，避免源码固定到旧版本而子模块仍留在另一版本。
- 为固定 curl/OpenSSL 快照补入 ASN.1 API 检测。
- 保留 libcurl 特性/静态依赖元数据校验，并在 mpv 构建前增加 Windows DLL 链接检查。
  检查 DLL 只用于构建验证，不运行，也不进入最终应用包。检查步骤显式依赖三个
  校验源码文件，仅修改这些文件时会重新检查，不必重新编译 curl。

## 提交前再次审查

再次审查确认并修复了两个遗漏：

1. 已完成的旧缓存缺少 `RECIPE` 时，原迁移逻辑直接写入当前指纹，可能错误接受旧
   产物。实际复现了同路径补丁由 v1 改为 v2 后，按 CI 的重新配置、下载、更新、构建
   顺序执行仍保留 v1 的情况。现在缺少指纹的缓存统一重建一次，并加入集成回归测试。
2. curl 的校验步骤缺少对检查脚本和链接检查源码的文件依赖，单独更新校验逻辑会
   被旧完成标记跳过。补齐依赖后，逐一修改三个文件均重新执行检查及 Windows DLL
   链接；curl 本身的配置、编译、安装不重复执行，紧接着再次构建仍报告无需操作。

首次使用新脚本可能重编大部分 Git 依赖包，不能承诺只重建失败的包。`mpv clang`
可以继续使用现有 LLVM 工具链缓存，无需手动删除；该工作流不因这些包的缓存迁移
而自动重编 LLVM。显式构建 LLVM 的工具链任务也会遵循新的 Git 缓存迁移规则。

## 验证范围

`tests/test_git_cache.py` 使用本地真实 Git 仓库、CMake 和 Ninja 验证缓存生命周期，
覆盖固定版本、分支前进、旧失败缓存、旧成功缓存的补丁更新、配置时源码修改、
成功清理、补丁重复应用防护、浅克隆，以及非 Git 依赖的清理路径。其集成用例实际编译并安装
一个静态 C 库，复现并验证“源码被重置但配置被跳过”的恢复过程。

Windows 网络依赖交叉编译使用独立临时目录和 LLVM-MinGW 23.1.3，编译本分支实际
配方及固定的 curl/OpenSSL/nghttp2/nghttp3/ngtcp2/c-ares/libpsl，并包括 libssh、
zlib、brotli、zstd。它能验证 Windows 源码兼容性和静态依赖链接；与生产 CI 的
Linux 宿主、LLVM 22.1.8、ThinLTO 及完整 mpv 依赖组合仍有区别。

本轮已完成的验证结果：

| 验证 | 结果 |
| --- | --- |
| 公共缓存回归测试 | 16 项通过，包含实际 C 静态库构建/安装及旧成功缓存补丁更新；新增两项均先复现失败、修复后通过 |
| Windows curl 网络依赖链 | 全部编译、安装通过；实际复现并修复 OpenSSL ASN.1 API 编译错误 |
| libcurl 特性与元数据 | HTTP2/HTTP3、OpenSSL、NativeCA、ECH、DNS、SSH、压缩等校验通过 |
| Windows DLL 静态链接 | 通过；检查导入表，没有新增 curl/OpenSSL/其他网络库或 winpthread DLL 依赖 |
| 校验源码变更与缓存复用 | 三个校验文件分别更新后均重新检查并链接 Windows DLL；不重编 curl，下一次构建无需操作 |
| 最终 curl 配方完整执行 | 两个源码补丁、编译、安装、特性检查、DLL 链接和清理全部通过；随后 force-update 和再次构建报告无需重编 |
| 真实 libvpl 配方 | 用新公共脚本完成 Windows x86_64 编译安装；随后 force-update 和再次构建报告无需重编 |
| mpv curl 策略测试 | 单元测试及 9 个本地网络场景全部通过 |
| ASN.1 包装函数 | 实际补丁代码的新 API 分支、旧 API 分支及非负长度转换检查通过 |

完整 Windows libmpv、最终 DLL、硬解和渲染功能仍需生产 CI 及 Windows 运行验证。

## 后续 CI 39189085214：libaribcaption 的 MD5 链接失败

本次构建运行于 `24e966b`，curl 已通过编译、特性检查和静态链接检查。
FFmpeg 在链接 `ffmpeg_g.exe` 时报告 `aribcc_md5_init`、`aribcc_md5_update`、
`aribcc_md5_final` 未定义；详细日志来自该运行的 `mpv-x86_64-logs` 产物。

libaribcaption 上游 `6c3b4f361bc8f65b34497ba0d123c5aea6f9ed84` 已将其
MD5 函数重命名为私有的 `aribcc_md5_*`，头文件不再通过 `HAVE_OPENSSL`
切换到 OpenSSL。然而 `md5.c` 仍用 `#ifndef HAVE_OPENSSL` 包住实现。
旧配方强制定义该宏，导致 `md5.c.obj` 虽然编译成功，却没有定义任何所需函数。

修复仅从 `packages/libaribcaption.cmake` 删除两个 `HAVE_OPENSSL` 编译宏及
该库过时的 OpenSSL 依赖，与 winbuild 上游
`b2856ee6deed6957380b32465f359e67f67fafd8` 的修复一致。
字幕解码和渲染开关保持开启；FFmpeg/curl 自身的 OpenSSL 依赖、FFmpeg 固定
版本和 mpv 配置不变。

已完成的针对性验证：

- 真实 `md5.c` 用 LLVM-MinGW 23.1.3、`-O3 -flto=thin` 编译：旧宏精确复现
  三个未定义符号，移除宏后符号齐全且 Windows DLL 链接成功。
- 同一 MD5 实现通过空串、`a`、`abc`、`message digest`、字母表五个 RFC 1321
  标准向量，确认恢复的是字幕字符匹配所需的哈希行为。
- 用真实解码器源码（含 `decoder_impl.cpp`）构建 Windows 静态库，并将实际
  `aribcc_decoder_decode` 调用与 OpenSSL/libcrypto 的 MD5 一起链接成 Windows
  DLL，未出现未定义或重复符号。这个隔离测试仅构建解码器；生产配方的渲染
  功能保持开启。
- 真实 Git/CMake/Ninja 的隔离依赖实验确认：仅改变 libaribcaption 配方，按 CI
  的重新配置、download、update、build 流程执行，即会重建该库及其 FFmpeg
  依赖者。无需改公共缓存脚本，也无需手动清空工具链或全部依赖缓存。

这些验证覆盖本次错误及重建路径；完整生产 LLVM 22.1.8 的 libmpv 构建仍由
下一次 GitHub CI 验证。

## 编译成功后如何验证目标

固定 FFmpeg 的 libavformat 版本是 `63.2.100`，满足 zcopy 源码中的默认 curl 启用
条件。该分支也包含 FFmpeg 嵌套 IO 的 curl 接入。当前 bota main 没有显式设置
`curl-reconnect-streamed` 或 `curl-retry-delay-max`；仓库补丁提供这些选项不代表
应用已经启用了它们。

1. 使用 `zc` 分支的 `mpv clang` 工作流，先构建 `x86_64`；`mpv_tarball` 保持关闭，
   确保使用自定义 zcopy 内核；取 `libmpv-x86_64-dev` 产物。
2. 确认应用实际加载了新 DLL，并从日志确认 curl 后端和 HTTPS 的 HTTP/2 协商。
   服务端必须支持 HTTP/2；仅有编译特性不证明每次请求使用 HTTP/2。
3. 使用相同地址、相同代理和相同缓存条件对比 `curl-enabled=yes` 与
   `curl-enabled=no`，记录打开耗时、首帧耗时及 seek 延迟。HTTP/3 单独测试，
   `auto` 不保证走 QUIC。
4. 回归直连/代理、鉴权、TLS 证书、重定向、HLS/DASH 子请求、拖动续播、取消、
   字幕加载，以及原有硬解/HDR/gpu-next。测试通过后才得出加载速度改善结论。
