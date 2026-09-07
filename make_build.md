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
