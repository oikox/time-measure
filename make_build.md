# sonic-vs.bin Make 构建耗时报告

## 结论

| 场景 | init | configure | build | 端到端 | 状态 |
|---|---:|---:|---:|---:|---|
| 完全冷构建 | 0:03.13 | 28:41.70 | 45:25.27 | 1:14:18 | 成功 |
| 保留依赖、产品冷、禁网 | 0:02.52 | 0:14.20 | 7:44.26 | 8:07.60 | 成功 |

保留依赖场景端到端减少 3970.40 秒（89.06%），约为完全冷构建的 9.14 倍速度；单独 build 阶段减少 2261.01 秒（82.96%），约为 5.87 倍速度。

## 固定参数

```text
PLATFORM=vs
NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1
NOBOOKWORM=1 NOTRIXIE=0
SONIC_BUILD_JOBS=8
SONIC_CONFIG_MAKE_JOBS=192
BUILD_SKIP_TEST=y
SONIC_CONFIG_USE_CCACHE=n
SONIC_DPKG_CACHE_METHOD=none
ENABLE_DOCKER_BASE_PULL=n
```

两轮均串行执行 `init`、`configure`、`target/sonic-vs.bin`，不清 Linux page cache，保留源码和子模块。

## 完全冷构建

执行入口：

```text
/data/sonic/时间统计/logs/20260901-233744/run-07-make-fully-cold.sh
```

清理范围包括仓库 ignored 构建树、`target`、`dpkg`、`fsroot-vs`、`fsroot.docker.*`、对应 slave 镜像和 Docker builder cache；版本缓存设为 `none`。

结果：

```text
开始：2026-09-05T18:30:21+08:00
结束：2026-09-05T19:44:40+08:00
退出码：0
产物大小：2354085871 bytes
SHA-256：ffbab213aab67b4a053d7b83e6426f8f2612c4b8711b26129bc81083f7507f18
```

证据目录：

```text
/data/sonic/时间统计/logs/20260901-233744/07-make-fully-cold
/data/sonic/时间统计/logs/20260901-233744/07-make-fully-cold-init
/data/sonic/时间统计/logs/20260901-233744/07-make-fully-cold-configure
/data/sonic/时间统计/logs/20260901-233744/07-make-fully-cold-build
```

## 保留依赖、产品冷、禁网构建

执行入口：

```text
/data/sonic/时间统计/logs/20260901-233744/run-08-make-deps-retained-offline.sh
```

正式 build 直接调用：

```text
BLDENV=trixie make -f Makefile.work MAKEFLAGS= \
  PLATFORM=vs NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 \
  NOBOOKWORM=1 NOTRIXIE=0 ENABLE_DOCKER_BASE_PULL=n \
  SONIC_CONFIG_USE_CCACHE=n SONIC_DPKG_CACHE_METHOD=none \
  SONIC_VERSION_CACHE_METHOD=rcache \
  SONIC_VERSION_CACHE_SOURCE=/data/sonic/时间统计/cache/20260901-233744/make-version-cache \
  BUILD_SKIP_TEST=y SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=192 \
  TRUSTED_GPG_URLS= target/sonic-vs.bin
```

正式环境同时设置无效 HTTP/HTTPS/ALL proxy、`GOPROXY=off`、`CARGO_NET_OFFLINE=true`、`PIP_NO_INDEX=1`、固定 Git mirrors，以及只读 rootfs、Cargo、Rust、Go、pip、APT、FIPS、debootstrap 等依赖输入。

清理只删除：

```text
fsroot-vs
target/sonic-vs.bin__vs__rfs.squashfs
target/sonic-vs.bin
```

不调用通用 `Makefile.work clean`，不删除 `target/vcache`、deb、wheel、Docker 依赖输出或 slave 镜像。configure 后使用单一参考时间戳刷新所有 retained 输出，避免 `.platform` 与遍历顺序触发依赖重建；`MAKEFLAGS=` 阻止 `Makefile.work` 的 `-B` 强制重建。

结果：

```text
开始：2026-09-06T20:23:22+08:00
结束：2026-09-06T20:31:30+08:00
退出码：0
产物大小：3257386991 bytes
SHA-256：9d78b4b7ea8e3525f7f50a477077a512b33f6f74f8f222364b0b93369c7f1e45
```

有效性证据：

- `target/vcache` 清理前后 66 项目录/文件内容摘要逐字节一致。
- 正式日志失败标记为 0，成功 HTTP 获取为 0，网络阻断记录为 5。
- 正式日志中 `docker build`、`dpkg-buildpackage`、`cargo build`、`go build`、`cmake --build`、`ninja` 实际构建命令均为 0。
- 仅 `target/sonic-vs.bin` 产品目标实际完成；日志中的依赖 `building/finished` 行是 install/load 包装目标，不包含依赖编译命令。
- 30 个 retained Docker 输出逐层审计：`cache.tgz`、`pip-wheelhouse`、`rustup-home` 污染项为 0，总大小 4468913089 bytes。
- 最终 payload：`dockerfs.tar.gz` 1880090317 bytes，`fs.squashfs` 978423808 bytes，`fs.zip` 3257109783 bytes。

证据目录：

```text
/data/sonic/时间统计/logs/20260901-233744/08-make-deps-retained-offline
/data/sonic/时间统计/logs/20260901-233744/08-make-deps-retained-offline-init
/data/sonic/时间统计/logs/20260901-233744/08-make-deps-retained-offline-configure
/data/sonic/时间统计/logs/20260901-233744/08-make-deps-retained-offline-build
/data/sonic/时间统计/logs/20260901-233744/08-seed-clean-docker-outputs
```

## 说明

两轮均为成功样本，但构建时间跨越多日，期间为跑通完全冷和严格离线路径修复了构建系统问题，因此两个产物不是同一源码工作树状态下的可复现性对照，SHA-256 和大小不应直接比较。耗时数据用于比较两种缓存边界；如需严格同提交 A/B，需在冻结当前工作树后重新执行两轮。

## 真实性与缓存边界审计

### 完全冷样本

`1:14:18` 是单轮 `/usr/bin/time -v` 实测端到端时间，init、configure、build 分别为 `0:03.13`、`28:41.70`、`45:25.27`，各阶段及 runner 均退出 0。最终产物为 2,354,085,871 bytes，SHA-256 为 `ffbab213aab67b4a053d7b83e6426f8f2612c4b8711b26129bc81083f7507f18`。

计时前 runner 删除仓库 `target`、`dpkg`、`fsroot-vs`、`fsroot.docker.*`、子模块 ignored 构建输出和本轮对应的两张 SONiC slave 镜像，并执行 `docker builder prune -af`。同时设置 `SONIC_CONFIG_USE_CCACHE=n`、`SONIC_DPKG_CACHE_METHOD=none`、`SONIC_VERSION_CACHE_METHOD=none`。

该场景并非裸机级全冷：宿主仍有其他 Docker 镜像、基础镜像层和无法回收的 active builder cache，Linux page cache 也未清除。清理后 Docker 仍报告 113 张镜像、329.8GB，以及 83 项 active builder cache、13.82GB。因此更精确的口径是“仓库构建输出冷、对应 slave 镜像冷、允许网络”，不是“宿主所有输入与容器层全部清空”。

### 编译输出冷纠偏轮

最新纠偏轮在计时前记录 449 项旧输出，随后将 `target/debs`、`target/python-wheels`、顶层 `target/docker-*.gz`、`fsroot-vs`、named squashfs 和最终 bin 清空；清理后清单为 0，`target/vcache` 的 66 项摘要保持一致。

本轮详细目标日志证明执行了实际构建：

- 60 个 Debian 包日志包含 `dpkg-buildpackage` 或 `debuild`。
- 32 个 wheel 日志包含 wheel 构建过程。
- 30 个 Docker gz 日志均显示目标原先不存在、进入 BuildKit 并执行镜像保存。
- kernel 日志执行 `debian/rules clean`、`dpkg-buildpackage` 和真实 GCC/HOSTCC 编译。
- PI、BMv2、P4C 均执行 `debian/rules clean`、`dpkg-buildpackage` 及 C/C++/CMake 编译，而非仅复制旧 deb。
- 另有 Cargo、Go、CMake/Ninja 的实际执行记录。

Docker 日志中的 `CACHED` 共 38 处，均位于 `FROM` 基础镜像或清理辅助阶段；业务 COPY/RUN 层实际重新执行。构建配置显示 `USE_DOCKER_CACHE` 为空、ccache 关闭、DPKG cache 为 `none`，没有 Bazel、disk cache 或 remote cache 参与。

该轮有意保留并使用网络依赖输入缓存，包括 APT 索引和下载包、pip wheelhouse、Git mirrors、Cargo registry/toolchain、Go module/sumdb、debootstrap tarball、FIPS 下载包及 Docker 基础镜像。例如 rootfs 恢复 590 个 APT deb，docker-dash-engine 恢复 72 个，syncd/gbsyncd 各恢复 259 个。这些是下载输入，不是计时前保留的目标 deb、wheel 或 Docker gz。

该轮 init、configure、Make build 分别为 `0:02.56`、`0:14.10`、`40:11.76`；Make build 本身退出 0。端到端为 `40:28.70`，但运行期间仓库目录被外部改名，runner 最后仍按旧绝对路径核验产物而失败，因此该轮只能证明编译耗时和冷边界，不能登记为正式成功产物样本。

### 为何不是七八小时

历史上的七八小时是多个失败 attempt、依赖补齐和重跑的累计周期，不是单次成功构建时间。旧报告中的 `8:07.60` 表示 8 分 7.60 秒，也不是 8 小时。单轮约一小时与 8 路外层并行、192 路包内并行、跳过测试、保留基础 Docker 镜像及不清 page cache 的边界一致。

### 清空基础 Docker 镜像的影响

- 对允许网络的完全冷场景，清空 Debian、P4Lang 等基础镜像会增加镜像下载、解压和 slave 重建时间，因此一定更慢；具体增量必须实测，不能从当前日志可靠外推。
- 对正式禁网 retained 场景，基础镜像属于必要输入。若直接删除且没有先保存并离线加载对应镜像归档，构建不会只是变慢，而会在解析 `FROM` 或拉取镜像时直接失败。
- 若要测量“基础镜像也冷但仍禁网”，应先把固定 digest 的基础镜像保存为独立输入归档；计时内执行 `docker load` 并重建全部上层镜像，将加载成本计入结果。
