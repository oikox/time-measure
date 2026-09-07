# sonic-vs Bazel 构建耗时

| 缓存档位 | 样本 | Wall time | Bazel elapsed | Critical path | Actions | 定位 |
|---|---|---:|---:|---:|---:|---|
| 完全冷（含依赖下载） | `01-bazel-fully-cold-attempt3` | 52:05.54 | 3125.096 s | 2231.52 s | 21686 | 正式样本 |
| 保留 external/repository，全部输出冷 | `05-bazel-all-outputs-cold-attempt2` | 30:28.44 | 1828.095 s | 1817.00 s | 21686 | 正式样本 |
| 保留 external/repository，仅缓存 kernel+p4lang | `06-bazel-kernel-p4lang-cached-attempt2` | 14:31.85 | 871.629 s | 642.09 s | 18897 | 正式样本 |
| kernel 冷、p4lang 工作区产物热 | `03-bazel-deps-retained-attempt6` | 15:28.10 | 927.870 s | 696.49 s | 21686 | 混合诊断样本，不纳入正式比较 |

全量离线重编比完全冷减少 21:37.10（41.5%），耗时为完全冷的 58.5%。仅缓存 kernel+p4lang 比全量离线重编减少 15:56.59（52.3%），耗时为后者的 47.7%。

## 全量离线重编口径

- 保留 `output_base/external`（8.4 GiB）和 repository cache（2.6 GiB）。
- 执行 `bazel clean`，并删除 p4lang Make bridge 留在工作区的 deb、日志和源码构建树。
- 正式构建使用 `--repository_disable_download --disk_cache= --remote_cache= --experimental_remote_downloader=`。
- 将 HTTP/HTTPS 代理指向不可连接地址，确保计时期间不能下载。
- p4lang 使用本地 Debian source package 和 `dpkg-source -x`，以 `DEB_BUILD_OPTIONS=nocheck` 仅执行构建。
- 日志无下载、disk cache/remote cache 命中、错误或失败；退出码为 0。

### 正式命令

```bash
bazel --output_base=/data/sonic/sonic-dzf-time-measure/.measure/20260901-233744/bazel-fully-cold-attempt3/output-base build \
  --repository_cache=/data/sonic/sonic-dzf-time-measure/.measure/20260901-233744/bazel-fully-cold-attempt3/repository-cache \
  --repository_disable_download \
  --remote_cache= \
  --experimental_remote_downloader= \
  --disk_cache= \
  --action_env=BUILD_SKIP_TEST=y \
  --action_env=HTTP_PROXY=http://127.0.0.1:9 \
  --action_env=HTTPS_PROXY=http://127.0.0.1:9 \
  --action_env=http_proxy=http://127.0.0.1:9 \
  --action_env=https_proxy=http://127.0.0.1:9 \
  --profile=<evidence>/profile.gz \
  --build_event_json_file=<evidence>/bep.json \
  //platform/vs:sonic-vs-bin
```

### 关键 action

- KernelBuild：192.301 秒。
- p4lang PI：759.023 秒。
- p4lang P4C 依赖链（含 BMv2 前置）：1721.331 秒。
- P4C 位于 critical path，占 94.73%。

### 产物与证据

- 产物大小：1,882,277,871 字节。
- SHA-256：`ab71e3b793228d37232107207fad703b488bd387d68de58ccd42f1ddceea14e8`。
- 证据目录：`logs/20260901-233744/05-bazel-all-outputs-cold-attempt2/`。

## 仅缓存 kernel+p4lang 口径

kernel 与 p4lang action 均为 `local/no-sandbox`，不会进入 disk cache，因此采用同一 output base 选择性 seed：

1. 计时外准备 PI、BMv2、P4C 工作区 deb。
2. 执行一次 `bazel clean`。
3. 仅构建 `@sonic_linux_kernel//:kernel_amd64`、三个 p4lang deb 目标和 `@p4lang//:pi_runtime_layer`。
4. seed 后不再 clean，仅执行 `bazel shutdown`，再计时完整目标。

### Seed 命令

```bash
bazel --output_base=<output-base> build \
  --repository_cache=<repository-cache> \
  --repository_disable_download \
  --remote_cache= --experimental_remote_downloader= --disk_cache= \
  --action_env=BUILD_SKIP_TEST=y \
  @sonic_linux_kernel//:kernel_amd64 \
  @p4lang//:p4lang-pi_0.1.1-1.deb \
  @p4lang//:p4lang-bmv2_1.15.0-9.deb \
  @p4lang//:p4lang-p4c_1.2.4.2-2.deb \
  @p4lang//:pi_runtime_layer
```

Seed 用时 2:40.19（不计入正式样本）。日志证明 KernelBuild 实际执行，三个 p4lang workspace deb 均为 `is up to date` 并写入 Bazel 输出。

### 正式命令

与全量离线正式命令一致，仍使用 `--repository_disable_download --disk_cache= --remote_cache= --experimental_remote_downloader=`，但保留 seed 后的同一 output base。

### 有效性与结果

- 正式 wall time：14:31.85；Bazel elapsed：871.629 秒；critical path：642.09 秒。
- 18,897 actions，其中 2,791 action cache hits 对应 seed 目标及必要传递 action，其余 16,106 actions 仍需处理。
- 正式日志无 KernelBuild、无 `SONiC make (local)`、无下载及 disk/remote cache 命中。
- profile 中 kernel 只有 0.454 秒 `action dependency checking`，不存在 kernel 或 p4lang 的 `action processing` 执行事件。
- 关键路径转移到 libboost 解包、swss-common SWIG/C++ 编译和镜像组装。
- 产物大小：1,882,277,871 字节。
- SHA-256：`b988f155d9980b043d37b8e8f0bdf176bf1757970eb62fd0b4c96d94833c9993`。
- 证据目录：`logs/20260901-233744/06-bazel-kernel-p4lang-cached-attempt2/`。
- Seed 证据：`logs/20260901-233744/06-bazel-kernel-p4lang-cached-attempt2-prep/`。

## attempt6 混合样本说明

attempt6 虽执行了 `bazel clean`，但未删除 p4lang Make bridge 的工作区 `target/debs`，日志明确显示 PI/P4C `is up to date`；kernel 则实际重编。因此其 15:28.10 不能代表“全部输出冷”或“仅缓存 kernel+p4lang”。
