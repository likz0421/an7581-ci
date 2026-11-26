# FTTR 前后端修复 — 交付说明

包含两条路径：**① v33 全量固件（驱动编 2 个 fttr + 全部修复，推荐刷机）** 与 **② 在线增量升级包（不重刷固件，仅前端）**。

---

## 路径 ①：v33 全量固件（2026-11-26，编译中）—— 真正解决"16 个 fttr"

> v31/v32 都没有真正减少 fttr 接口：v31 前端 bundle 还是旧版，v32 不含驱动改动（已取消）。
> **v33 是本轮按你要求重做的版本，编译完成后会替换这里。**

v33 包含你这一轮要求的全部改动：

1. **驱动层真正只编 2 个 fttr  netdev**（不是隐藏）：`fmcs.h` 新增 `FMCS_ACTIVE_FTTR_PORTS=2`，
   创建循环只注册 `fttr1`、`fttr2`；系统 `/sys/class/net` 里不再有 fttr3~fttr16。
   保留 `FMCS_MAX_FTTR_PORTS=16` 作数组容量与协议上限（RX 路径按 GEM 0x100-0x10f 下标访问，
   降容量会越界崩溃），未用槽位为 NULL 且所有访问有保护。以后想改成 N 个，只改这一个宏即可（1-16）。
2. **后端对齐到 2**：桥接范围、配置校验、status 上报都限制为 1-2，与驱动一致，不再产生幽灵端口。
3. **前端显示=真实**：下联端口/拓扑只信任后端 status 上报的实际桥接口数，不再各自读 UCI 猜测。
4. **中文化**：FTTR LAN 端口数等设置项与说明已补中文翻译（之前缺翻译才显示英文）。
5. **拓扑图大改**：改成纯 SVG 分层拓扑（OLT 根节点 → 连线 → 各端口节点，UP 绿色/DOWN 灰色），
   去掉脆弱的 G6/snapshot ubus，端口数跟随真实桥接数。

编译前已做静态验证：驱动括号配平/范围断言/零初始化确认、后端三处 1-2 且测试同步、
前端 typecheck+build 通过（产物无 uci.load、无 G6、含 SVG）、一键脚本端到端测试全绿。

- 构建 run：`45735310762`（build-an7581），Release `v33` 编完后发布在此：
  https://github.com/likz0421/an7581-ci/releases
- 刷机用 `ponwrt-airoha-an7581-h3c_hm2004-du-squashfs-sysupgrade.itb`；
  recovery 用 `...initramfs-recovery.itb`。刷机选「不保留配置」以应用默认 IP 10.1.1.1 / WiFi hanzi。

v33 编完我会做二进制级验证（确认驱动只创建 2 个 fttr、bundle md5、中文翻译、后端 1-2 校验）后再给最终确认。

---

## 路径 ②：不重刷固件 — 一键脚本（离线自包含，大陆网络友好）

适用于暂时不想刷机、只在当前固件上在线看前端修复的场景。**注意：此路径改不了驱动**，
系统里的 fttr3~fttr16 netdev 依旧存在，只有 v33 固件能从驱动层去掉。

`fttr-oneclick.sh` 把三个前端 bundle 以 base64 **全部内嵌**，升级过程不访问 GitHub 或任何外网，
只需 scp 这一个文件到设备即可完成检测、安装、状态查看和卸载回退：

```bash
scp online-fix/fttr-oneclick.sh root@10.1.1.1:/tmp/
ssh root@10.1.1.1
sh /tmp/fttr-oneclick.sh check       # 只读检测：OpenWrt 版本/架构、apk 或 opkg、LuCI 路径、fttrd、lan_ports
sh /tmp/fttr-oneclick.sh all         # 一键：备份 -> 安装 -> md5 校验 -> 清 LuCI 缓存
sh /tmp/fttr-oneclick.sh status      # 查看三个 bundle 的安装版本与 md5
sh /tmp/fttr-oneclick.sh uninstall   # 从最近备份恢复，可随时回退
```

后端修复已编进 v33 固件（v31/v32 不含）；若你暂时只想在旧版上补后端，可把 `openwrt-fttr-*.apk`
scp 到设备，用**同一个脚本**带参数安装（同样不访问外网；单包编译不可行，见文末说明）：

```bash
scp openwrt-fttr-*.apk root@10.1.1.1:/tmp/
sh /tmp/fttr-oneclick.sh all /tmp/openwrt-fttr-xxxx.apk
```

脚本特性：

- 自动识别设备实际 LuCI 目录（`/www/luci-static/...` 或 `/usr/share/luci/htdocs/...`），不写死路径。
- 覆盖前自动备份到 `/etc/fttr-oneclick/backup/<时间戳>/`；任一文件校验失败自动回滚。
- 写入后逐文件 md5 校验，避免传输出错导致 LuCI 白屏。
- `check` / `status` 完全只读，可先跑一遍确认设备现状。
- 文件 md5（本轮最终）：config `98a240c276241defdb6b4b8d1c2f3f5f` / index `4db5aee8ca5c2ea299f95e90c8376cf2` / topology `8b66abbf1da7cb17f15b1cbcc16c67df`；脚本 md5 `9b3f5ae5ab41e51cc6543ae77e006354`。

下面的"方式 A / 方式 B"是手动等效步骤，供不想用脚本时参考。

---

## 本轮（第 3 轮）新增修复：端口数统一 + 拓扑图重做

用户实测反馈：把 `FTTR LAN port count` 设为 1、br-lan 里确实只剩 1 个 fttr 口了，但
**FTTR 前端"下联端口"页仍画 16 张卡、拓扑图节点一大堆、还报一堆问题**。

根因（三处互相独立）：

| 现象 | 真正来源 |
| --- | --- |
| br-lan 桥了 16 个口 | 后端 `setup_bridge`（上一轮已修，按 N 桥接） |
| 前端下联端口仍 16 张卡 | 后端 `status.switch_ports` 按 `ONU_COUNT=16` 生成，前端照单全收 |
| 拓扑图问题多、 stale / unavailable | upstream 用 AntV G6 + 三个脆弱 ubus 接口（`get_topology`/`_node`/`_clients`）+ snapshot 机制，定制固件上频繁不可用 |
| 网络→设备页 fttr1~16 | 内核驱动 `fmcs` 硬编码注册 16 个 netdev（本轮按约定**不动驱动**） |

修复策略（界面层根治，把 `fttr.h3c.lan_ports=N` 作为唯一真相源）：

1. **`index.js`（概览页）**：H3C 平台从 UCI 读 `lan_ports`，下联端口**只画 fttr1..fttrN**，
   多余的端口数在页首折叠为一行说明。
2. **`topology.js`（拓扑页）**：**完全重写**——去掉 AntV G6 重依赖和 snapshot 链，
   改为基于稳定的 `get_status` 的轻量分层视图（OLT 控制器 → N 条 PON 下联 → 已注册 ONU），
   同样只显示 N 条分支。bundle 从含 G6 的体量降到 **63 kB**，不再出现 `sources unavailable / stale snapshot / issues`。
3. **`config.js`（配置页）**：沿用上一轮修复（`Saved/active 1/16·待重启` 误报已改、H3C h3c section 正常创建）。

---

## 之前（第 2 轮）修复的 Bug

| # | 现象 | 修复 |
| --- | --- | --- |
| 1 | `unsupported section: h3c` / "已提交的配置无效" | 后端 `templates.rs` 把 `h3c` 加入合法 section 并校验 `lan_ports` 1~16（需 apk 升级） |
| 2 | 前端一直显示 `Saved / active ports 1 / 16 · 待重启生效` | 前端移除错误的 active 对比，改为准确说明（H3C + FiberHome 都修了） |
| 3 | NPU 页 `PPE counters: unavailable, invalid or overflowing` | 后端仅在真正采样到 flow 但数据无效时才报错，空闲不再塞错误（需 apk 升级） |

---

## 升级方式 A：前端立即生效（无需编译，立竿见影）

前端 3 个 bundle 都是自包含 JS，直接 scp 覆盖设备文件即可。设备 IP 若改过，把 `10.1.1.1` 换成实际地址。

```bash
scp online-fix/frontend/config.js   root@10.1.1.1:/www/luci-static/resources/view/fttr/config.js
scp online-fix/frontend/index.js    root@10.1.1.1:/www/luci-static/resources/view/fttr/index.js
scp online-fix/frontend/topology.js root@10.1.1.1:/www/luci-static/resources/view/fttr/topology.js
```

然后在浏览器**强制刷新** LuCI（Ctrl+F5），验证：

- FTTR → 概览：下联端口只显示 N 张卡，页首说明"显示 N 个活跃端口，其余已隐藏"。
- FTTR → 拓扑：只显示 N 条下联分支，不再有陈旧/不可用提示。
- FTTR → 配置 → 基本：`FTTR LAN port count` 仍是你的设置值，文案不再是 `1/16·待重启`。

> 前端 bundle 覆盖了 `index.js`、`topology.js` 即生效；`config.js` 只有上一轮没覆盖过的设备才需要传。

## 升级方式 B：后端 apk（修复 bug #1、#3，可选）

> **状态更新（重要）**：后端 apk 单包编译已证实不可行——fttr 包依赖内核模块 `kmod-h3c-fmcs`，
> 连带要 prepare 整个内核，且 Rust 编译器从源码自举要 88 分钟，本质是"半个固件编译"。
> 这两个后端 bug（配置校验误报、PPE 空闲提示）不影响功能。经决策改为**全量固件编译 v31**
> （`build-an7581` run `45704267034`，进行中），一步到位含前后端全部修复，刷机后即无需任何在线覆盖。
> 以下方式 B 的 apk 路径仅作历史保留，不再推荐。

后端 fttrd 是编译后的二进制，需升级 apk。GitHub Actions workflow `build-fttr-packages`
首次 run `45612411796` 编译失败（make 目标名用了 Package 名 `openwrt-fttr`，
但 feed 里的真实目录是 `fttr`）。修复后 run `45619341303` 仍失败（内核依赖 + Rust 自举耗时）。
若将来从该 workflow 的 artifact `fttr-packages` 拿到 `openwrt-fttr-*.apk`，传到设备：

```bash
scp openwrt-fttr-*.apk root@10.1.1.1:/tmp/
ssh root@10.1.1.1
cd /tmp && apk add --allow-untrusted openwrt-fttr-*.apk
/etc/init.d/fttr restart
ubus call fttr config_check   # 期望 {"valid":true,...}，不再报 unsupported section
```

- 只想要界面马上正确：做方式 A 即可，无需等后端 apk。
- 想连配置校验/NPU 提示一起修：等 apk 编译完再做方式 B。

---

## 为什么这样升级

- 全量固件编译约 1h48m，改个小 bug 都重刷固件太慢。
- 前端是纯 JS，覆盖文件零编译、立即生效、不碰任何配置。
- 后端单独编译 apk 在线安装，不动现有 LAN/WiFi/FTTR 端口数设置。

## 关于「重新编译固件」与「要不要动驱动」

**Q：单纯重新编一个固件，设备里那 16 个 fttr netdev 会变少吗？**

**不会。** 这 16 个接口来自内核驱动 `fmcs`，源码里是写死的：

- `fmcs.h:114` → `#define FMCS_MAX_FTTR_PORTS 16`
- `fmcs_netdevs_init()` → `for (i = 0; i < FMCS_MAX_FTTR_PORTS; i++) { ... register_netdev("fttr%d", i+1); }`
- 驱动**没有任何端口数 module_param**，`netdev_ops` 里也没有 `ndo_dellink`，用户态删不掉。

所以只要源码不改，重编多少次、刷多少次固件都还是 16 个。驱动有没有参数可实测：
`ls /sys/module/fmcs/parameters/`（本固件里只有 offload/spi 相关参数，没有端口数）。

**Q：那要不要动驱动？**

| 方案 | 收益 | 代价 / 风险 |
| --- | --- | --- |
| 界面层收敛（已交付） | FTTR 概览/拓扑/配置只显示 N 个；纯 JS 在线覆盖，零业务中断 | 网络→设备页内核 netdev 仍 16 个（客观存在） |
| 改驱动参数化重编 kmod | 开机只注册 N 个 netdev，设备页也只剩 N 个，物理根治 | 需把循环上限改成可配置，并给所有按 port 访问 `fttr_devs[]` 的位置（约 8 处）补边界/NULL 检查，否则 port>N 会内核 oops；在线替换 kmod 瞬间 PON 断流，且与 fttrd/FPGA 强耦合 |

**建议：当前不动驱动。** 先用已交付的界面层收敛满足"只看 N 个"的诉求（低风险、即时生效）；
驱动改造放到下一次固件构建窗口一并做，避免在线替换内核模块打断业务。若确定要做，
下一步可以把 `fmcs` 的端口数参数化补丁准备好推到 fork，随下次固件编译生效。

## 提交记录

- 前端 `likz0421/luci-app-fttr`
  - main @ `3884317`：`fix(fttr ui): filter downstream ports by lan_ports; replace G6 topology with lightweight status-based view`
  - package @ `9eec61a`：9 个 bundle（config/index/topology 等）
- 后端 fork `likz0421/openwrt-fttr` 分支 `an7581-custom` @ `8fb254e`（config_check h3c + PPE counters）
- CI 单包 workflow `.github/workflows/build-fttr-packages.yml`（commit `f76c3e0`）
