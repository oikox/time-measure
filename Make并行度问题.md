# 资源占用
当前资源占用：机器基本是闲着的
刚采的样本（mpstat 2 3，三次一致）：
指标	数值	判断
CPU	%usr 1.06 / %sys 0.06 / %idle 98.88	192 核用了约 2 核
Load avg	6.16 / 15.33 / 16.63	相对 192 核 ≈ 3~8%
R 状态进程	3 个（S 968 / I 891）	几乎没有可运行任务
内存	33G used / 742G，702G 在 buff/cache	完全不是瓶颈
磁盘	nvme1n1 写 ~45MB/s，%util 5.65，iowait 0.0	完全不是瓶颈
/data	483G used / 1007G，剩 474G	够，但比昨天涨了 278G，留意
不是 IO 瓶颈、不是内存瓶颈、就是没活干。
现在跑的是什么
02-make-fully-cold-attempt15，build 子步骤已跑 18 分 39 秒。CPU 前几名：
178%  test_parser      ← p4lang bmv2 单测
137%  test_actions
101%  qemu-system-i386
 17%  test_queueing
还有一个很扎眼的：
make -j1 check TESTSUITEFLAGS=-j1 --verbose VERBOSE=1
正卡在串行单测尾巴上。
根因：SONIC_BUILD_JOBS 被夹到了 8
rules/config#L20 的自动探测公式是 min(nproc/4, ram_gb/8)，然后 clamp 到 [1, 8]。我按你的机器实算了一遍：
cores=192  ram=742G  by_cores=48  by_ram=92  =>  SONIC_BUILD_JOBS=8
by_cores 算出 48、by_ram 算出 92，结果被那个 clamp to 8 砍到 8。而外层 make 命令行没传 SONIC_BUILD_JOBS，所以走的就是这个默认值。所以：包级并发只有 8 路（单个包内部倒是给了 -j192，我看到 dpkg-buildpackage -j192）。8 路里现在好几路都在跑 -j1 的串行单测 → 全机 1% 利用率。
这件事对你的测量意义很大
Bazel 默认 --jobs=auto ≈ nproc（192），Make 这边包级只有 8。这个不对称会直接主导两边的冷构建时长差，而且它衡量的不是"Make vs Bazel 构建系统效率"，而是"这个 clamp 值设成了 8"。我倾向于建议：显式指定，两边对齐，比如 Make 侧加 SONIC_BUILD_JOBS=48（by_cores 的原始值），Bazel 侧 --jobs=48；或者两边都放开到 192。然后在报告里写明用的并发度。现在这个跑法测出来的 Make 数字会偏大很多，容易被质疑"你没给 Make 开满并发"。不过这是方法论选择，不是 bug——如果你的口径就是"各自默认配置下的开箱时长"，那 8 就是 Make 的默认，照测也站得住。需要你决定，我不建议我替你改一个正在跑的测量。

# 测量影响
对测量的影响
Bazel 的 --jobs 默认 auto ≈ nproc = 192，而且它调度的是单个 action（一次编译、一次打包），没有"包"这层粗粒度屏障——串行段天然被别的 action 填满。所以：
现在这一跑是 Make 包级 8 路 vs Bazel action 级 192 路
差的很大一部分是调度粒度和并发度，不是"构建系统本身的效率"
三个口径，你选一个（我不建议我替你改正在跑的测量）：
默认对默认：Make 用 fork 默认（8），Bazel 用默认（auto）。好处是"开箱体验"真实，坏处是数字里混了并发度差异。
并发对齐：Make SONIC_BUILD_JOBS=48，Bazel --jobs=48。最能体现构建系统本身差异。
都放开：Make SONIC_BUILD_JOBS=192，Bazel 默认。有 OOM 风险（那个 clamp 就是为内存安全设的，注释写着每个包可能吃 8G），但你有 742G 内存，48 路×8G=384G 还算安全，192 路就危险了。