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
| LAN IP | `10.1.1.1/24` | `/etc/uci-defaults/10-hanzi-defaults`：首启（含 sysupgrade 后首启）检查，仍是 192.168.1.1 才改 |
| DHCP | 从 `10.1.1.2` 起、顺序分配、租约 `36h` | 同上；仍是出厂 100/150/12h 才改 |
| WiFi 2.4G/5G | SSID `hanzi`，WPA2 密码 `hanziwawa` | `/etc/rc.local`：服务启动后改名，覆盖所有射频（全新刷机首启即生效） |

> **想让它生效**：刷机时选 **不保留配置**（sysupgrade `-n` / LuCI 取消勾选 "保留设置"）。
> 保留旧配置时会话保留你原来的 SSID/密码，只有仍为出厂值的项会被改写。

改默认值：编辑 [files/](files/) 下对应脚本，push 后重编。

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

1. **下载固件**：[Actions](https://github.com/likz0421/an7581-ci/actions) 下载 `an7581-run-<N>` 工件
2. **刷机**：先备份 factory 分区（PON 校准/身份）；首次用 [an758x-stock2ubi](https://github.com/pbs05/an758x-stock2ubi)；已刷 PonWrt 直接 sysupgrade
3. **改包**：编辑 [.config.additions](.config.additions) / [.config.fttr](.config.fttr) 后 push 自动重编
4. **手动触发**：Actions → Run workflow（`ponwrt_ref` / `with_fttr` / `pon_userspace_pr16`）

## 失败诊断

Actions 日志在部分网络下 403。工作流失败时会把失败步骤末尾写进 check-run 注解（Actions 页面可见），同时把日志尾部提交到 `diagnostics/` 目录；configure 里程碑也会打进注解。

## 注意

- 每周一 14:00（北京时间）自动跟 PonWrt master
- OLT 侧 NPU 卸载 / 下行光口散热是上游问题
- 本仓库不存个人 token，CI 用内置 GITHUB_TOKEN
