# an7581-ci

H3C HM2004-DU（Airoha AN7581）PonWrt 自动编译，只看需要的这几样：

- **eBPF Honk** 透明代理（[kenzok8/openwrt-honk](https://github.com/kenzok8/openwrt-honk)：honk 核心 + Doona 界面 + LuCI 管理页）
- **芯片状态** [luci-app-airoha-npu](https://github.com/rchen14b/luci-app-airoha-npu)：AN7581 NPU/CPU 频率/Frame Engine/PPE 流表监控
- **openFTTR** [LazuliKao/openwrt-fttr](https://github.com/LazuliKao/openwrt-fttr)：OLT 驱动 + fttrd 控制器 + [likz0421/luci-app-fttr](https://github.com/likz0421/luci-app-fttr) 前端（修过毛玻璃/深色对比度/窄屏排版）
- **PON 光模块状态卡片**：pbs05/openwrt-pon-userspace [PR #16](https://github.com/pbs05/openwrt-pon-userspace/pull/16)
- 基线 [pbs05/ponwrt](https://github.com/pbs05/ponwrt) master（`h3c_hm2004-du`，内核 6.18）
- **Passwall 全家桶已关闭**

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
