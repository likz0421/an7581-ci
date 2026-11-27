# an7581-ci

H3C HM2004-DU（Airoha AN7581）PonWrt 自动编译，只看需要的这几样：

- **eBPF Honk** 透明代理（[kenzok8/openwrt-honk](https://github.com/kenzok8/openwrt-honk)：honk 核心 + Doona 界面 + LuCI 管理页）
- **芯片状态** [luci-app-airoha-npu v1.3.1](https://github.com/DenzelVincent/luci-app-airoha-npu)：AN7581 NPU/CPU 频率/Frame Engine/PPE 流表监控（中文界面）
- **openFTTR** [LazuliKao/openwrt-fttr](https://github.com/LazuliKao/openwrt-fttr)：OLT 驱动 + fttrd 控制器 + [likz0421/luci-app-fttr](https://github.com/likz0421/luci-app-fttr) 前端（修过毛玻璃/深色对比度/窄屏排版 + 上游光模块遥测）
- **PON 光模块状态卡片**：pbs05/openwrt-pon-userspace [PR #16](https://github.com/pbs05/openwrt-pon-userspace/pull/16)
- 基线 [pbs05/ponwrt](https://github.com/pbs05/ponwrt) master（仅 `h3c_hm2004-du` 设备，内核 6.18）
- **Passwall 全家桶已关闭**

## 出厂默认值（files/ 覆盖层）

| 项目 | 默认 | 生效方式 |
| --- | --- | --- |
| LAN IP | `10.1.1.1/24` | 首次启动由 `/etc/uci-defaults/10-hanzi-defaults` 写入 + `/etc/rc.local` 兜底 |
| DHCP | 从 `10.1.1.2` 起、顺序分配、租约 `36h` | 同上 |
| WiFi 2.4G/5G | SSID `hanzi`，WPA2 密码 `hanziwawa` | `/etc/rc.local`：首次启动覆盖所有射频 |

> **生效机制（仅首次刷机）**：全新刷机第一次开机检测到标记文件 `/etc/hanzi-defaults-applied` 不存在，
> 无条件写入 IP/DHCP/WiFi 并打标记；之后每次开机 / 保留配置升级都不再改动，
> 你在网页上改的 IP/WiFi 不会被覆盖。不再依赖 `192.168.1.1` / `OpenWrt` 这些出厂字符串判断。

改默认值：编辑 [files/](files/) 下对应脚本，push 后重编。

## FTTR 接口数量（H3C HM2004-DU）

**v37 起固件在驱动层只创建 2 个 fttr 下行口（fttr1、fttr2）**——不是前端隐藏，是 kmod 真实注册数量，
`FMCS_ACTIVE_FTTR_PORTS=2`（结构体数组容量仍为 16 以支持硬件编号）。后端桥接与前端拓扑图都只认这 2 个口，
后端 `switch_ports` 为单一真相源，前端不再自行猜测端口数。

- **网页改**：FTTR → 配置 → 基本 → **下联端口数量**（1~2），保存后点 **Restart** 重启 fttrd 生效。
- **命令行改**：`uci set fttr.h3c.lan_ports=2 && uci commit fttr && /etc/init.d/fttr restart`
- 早期版本曾支持 1~16 的 `lan_ports` 配置，但驱动层已收窄，超过 2 的值会被拒绝。

> 该能力来自后端 fork [likz0421/openwrt-fttr `an7581-custom` 分支](https://github.com/likz0421/openwrt-fttr)
> 与前端 [likz0421/luci-app-fttr](https://github.com/likz0421/luci-app-fttr) package 分支，
> `configure.sh` 已把 fttr feed 指向该分支。

## PON 状态页增强（v41 起）

- **光功率趋势**：每张 PON 线路卡片显示最近约 2 分钟的接收光功率曲线（SVG sparkline），数据只存浏览器内存，不写 flash。
- **弱光告警**：接收光功率低于 -27 dBm 时卡片和曲线标红并显示"光信号偏弱"徽标。
- **链路事件时间线**：页面打开期间生命周期状态变化（如掉线/重连）按时间倒序列出，最近 30 条。
- **导入/恢复 diff 确认**：导入配置或恢复备份前先弹出"将改变哪些项"的清单，人工确认后才执行，且始终先备份当前配置。

> 这些是纯前端改进，不涉及后端/驱动；趋势与事件是页面生命周期内的观察数据，刷新页面后重新累积。

## 当前推荐固件：v44

[Release v44](https://github.com/likz0421/an7581-ci/releases/tag/v44) = 全部修复的最终版，二进制验证 37/37 通过：

- 下载 `...-squashfs-sysupgrade.itb`（36.1MB）sysupgrade 即可；已刷 v39+ 的可保留配置升级。
- **FTTR `Object not found` 根治**：真机日志确认硬件初始化失败会 `process::exit(1)` 导致 ubus 对象消失。v44 的 fttrd 改为进程内重试 3 次 + 失败后进入 degraded mode 保持进程/ubus 存活，前端能读到降级状态而非报错。
- **dnsmasq 按顺序分配 IP**：补齐 `sequential_ip=1`（出厂默认 + rc.local 兜底 + 保留配置升级迁移脚本）。
- **PON 全中文**：补齐菜单（备份/恢复、在线更新等）与页面所有英文遗漏，316 条文案零遗漏。
- **PON 线路健康总览**：线路总数/在线/弱信号/错误/最低光功率五项统计卡。
- v41/v42/v43 的全部内容（vantage 主题、SVG 拓扑、光功率趋势、链路事件、导入 diff 确认、ponctl JSON、honk beta7）均已包含且未回退。

<details><summary>v40 变更明细（历史）</summary>

[Release v40](https://github.com/likz0421/an7581-ci/releases/tag/v40) = 当时全部修复的超集，二进制验证 35/35 通过：

- **FTTR**：驱动层 2 口 + 桥接修复（fttrd 不再对不存在的 fttr3~16 做 `ip link`，避免 `Object not found`/硬件初始化失败）+ 全中文界面 + SVG 分层拓扑图（无 G6）。
- **主题**：移除 argon，默认 `luci-theme-vantage`（首启自动切换）。
- **PON 插件**：状态仪表盘 + 单页傻瓜式配置 + 一键导入导出 + **真在线更新**（GitHub releases → wget → sha256 → apk add，更新源可经 `pon.update.release_url` 改）+ ponctl `status --all --json` / `version --json`。
- **honk**：beta.7 已含。
- 刷机：已刷 PonWrt 直接 sysupgrade；首次刷先备份 factory（PON 校准/身份）。保留配置升级不会覆盖你改过的 IP/WiFi。

</details>

## 构建守卫（发版前自动检查，避免"构建成功但固件缺东西"）

1. `configure.sh` 在 `make defconfig` 后校验必需包必须为 `=y`，缺一个直接失败
2. `make defconfig` 遇到上游 feed 的 kconfig 递归依赖错误会自动摘掉坏包重试（最多 4 次）
3. 构建后 `Verify build outputs` 检查 apk/ipk 产物是否真的存在（同时兼容 `name_version.ipk` 和 `name-version.apk` 两种命名），并强制要求 HM2004 sysupgrade itb 存在，缺包拒绝发版
4. 每次构建都把产物清单（itb + 相关 apk/ipk）提交到 `diagnostics/manifest-run-N.txt`

## 内核选项（configure.sh 自动注入 `target/linux/airoha/an7581/config-6.18`）

```
CONFIG_DEBUG_INFO_BTF=y    # honk CO-RE 必需
CONFIG_CGROUP_BPF=y        # cgroup v2 eBPF
CONFIG_NET_CLS_ACT=y       # TC-bpf
CONFIG_NET_XGRESS=y
CONFIG_FUNCTION_TRACER=y
CONFIG_DYNAMIC_FTRACE=y
```
PPE 流表依赖的 `CONFIG_DEBUG_FS=y` 已在通用内核配置里；Frame Engine 寄存器读写需要 busybox `devmem`（已在 .config.additions 打开）。

## 用法

1. **下载固件**：优先用 [Release v40](https://github.com/likz0421/an7581-ci/releases/tag/v40) 的 `...-squashfs-sysupgrade.itb`；历史构建在 [Actions](https://github.com/likz0421/an7581-ci/actions)
2. **刷机**：先备份 factory 分区（PON 校准/身份）；首次用 [an758x-stock2ubi](https://github.com/pbs05/an758x-stock2ubi)；已刷 PonWrt 直接 sysupgrade
3. **改包**：编辑 [.config.additions](.config.additions) / [.config.fttr](.config.fttr) 后 push 自动重编
4. **手动触发**：Actions → Run workflow（`ponwrt_ref` / `with_fttr` / `pon_userspace_pr16`）

## 失败诊断

Actions 日志在部分网络下 403。工作流失败时会把失败步骤末尾写进 check-run 注解（Actions 页面可见），同时把日志尾部提交到 `diagnostics/` 目录；configure 里程碑也会打进注解。

## 注意

- 每周一 14:00（北京时间）自动跟 PonWrt master
- OLT 侧 NPU 卸载 / 下行光口散热是上游问题
- 本仓库不存个人 token，CI 用内置 GITHUB_TOKEN
