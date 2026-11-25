# 2026-11-24 夜间/上午工作日志

## 最终可用固件（2026-11-25 中午）
**Release v16**（构建 #16，green，当前唯一版本）：
https://github.com/likz0421/an7581-ci/releases/tag/v16

HM2004 刷机文件（Release 里只有 2 个附件，其他设备已不编）：
- `ponwrt-airoha-an7581-h3c_hm2004-du-squashfs-sysupgrade.itb`（35.8MB，sysupgrade 升级）
- `ponwrt-airoha-an7581-h3c_hm2004-du-initramfs-recovery.itb`（29.8MB，救援）

## 出厂默认值（v16 起内置，files/ 覆盖层打进 rootfs）
- LAN = 10.1.1.1/24（board.d/zz-hanzi-net，首启且仍为 192.168.1.1 时生效）
- DHCP 从 10.1.1.2 起、顺序分配（dnsmasq 默认行为）、租约 36h（board.d/zz-hanzi-dhcp）
- WiFi 2.4G/5G SSID hanzi / WPA2 密码 hanziwawa（uci-defaults/10-hanzi-wifi，
  幂等：只改写仍是出厂 OpenWrt 的 SSID，改过就不动）

## 关键修复时间线
1. feeds 名不能带横线（Syntax error）→ honk/fttr/fttrui
2. Release 没附件：固件实际是 **.itb 不是 .bin**（H3C 设备用 FIT 镜像）
   → glob 改为 `**/*.itb` + `**/*.bin`
3. **PonWrt 默认 config 没选 h3c_hm2004-du 设备** → 前几次"成功"构建
   都没有 HM2004 固件；.config.additions 加设备选择 + configure.sh 校验
4. upload-firmware 补传流：乱码文件、tar 读不了 GitHub zip、gh 缺 -R 仓库
   上下文、缺 .itb 匹配，全部修复
5. 只编 HM2004：取消默认 config 里其他 13 种 AN7581 设备（体积 885MB→70MB）
6. NPU 应用换成 DenzelVincent v1.3.1（中文，PPE 寄存器/CDM 占比/主题自适应）
7. files/ 覆盖层打进出厂默认值（Windows 反斜杠路径事故：tree API 删不掉
   反斜杠文件名，改用整树重建解决）
8. 清理：失败/取消构建全删；#7~#15 与 v11/v12/v14 已删，只留 #16 + v16

## 固件规格（最终版）
PonWrt master（AN7581，内核 6.18）+ 以下插件，Passwall 全家桶关闭：
- eBPF Honk 透明代理（honk + luci-app-honk，kenzok8 feed 最新稳定版）
- 芯片状态：luci-app-airoha-npu v1.3.1（DenzelVincent，NPU/CPU/Frame Engine/PPE）
- openFTTR：OLT 驱动 + fttrd 控制器 + 前端（上游光模块遥测 + 显示修复）
- PON 光模块状态卡片：pbs05 PR#16（DenzelVincent fork）
- 目标设备：仅 h3c_hm2004-du

## 本次完成的事
1. **feeds 语法修复**：OpenWrt feeds 解析器要求 feed 名 `\w+`（无横线），
   openwrt-honk→honk、openwrt-fttr→fttr、fttr-ui→fttrui。构建 #5→#7 因此转绿。
2. **芯片状态插件**：确认就是 rchen14b/luci-app-airoha-npu，替代之前误配的 cpufreq/statistics。
3. **Passwall 关闭**：an7581.config 默认带的全家桶逐项关闭（.config.additions）。
4. **FTTR 前端上游同步**：
   - 上游 11-23 新特性（概览页光模块遥测、MIB 诊断改进、i18n、AN4475 ONU 数量配置等）
     全部并入 fork main（commit d56bab1，基于上游 main 7f951a2 时代）
   - 保留 10 个文件的显示修复：毛玻璃前缀（WebkitBackdropFilter）、
     #888 弱对比标签 → opacity .72/.75、窄屏 minmax(min(100%,Npx)) 网格
   - 本地 pnpm build 重新生成 9 个 bundle（约 1.85MB），推 package 分支（18d8a68）
   - 已验证：topology.js 含 WebkitBackdropFilter，全部 bundle 无 #888 残留
5. **仓库清理**：删除失败/取消的构建记录 #1-#6，删除孤儿提交 6c35beaf，
   main 只留干净历史；成功构建 #7 保留（可刷）。
6. **自动发版**：工作流加 softprops/action-gh-release 步骤，
   以后每次成功构建自动创建 Release（附 .bin 镜像）。
7. **诊断通道**：失败时日志尾部自动写 check-run 注解 + diagnostics/ 提交
   （Actions 日志 403 时也能看错误）。

## 状态
- 构建 #7：成功（旧 fttr bundle），artifact an7581-run-7 可下载
- 构建 #8：进行中（新 fttr bundle + 自动 Release）
- 本地到 GitHub 网络 11:05 起中断（出国线路 ECONNRESET，国内正常），恢复后：
  - 读 #8 结果 → 成功则删除旧 #7 记录（cleanup-after8.js 已备好）

## 刷机
- Release/工件里找 `*-sysupgrade.bin`（已刷过 PonWrt）或 `factory.bin`（首刷）
- 验证：`uname -r`（6.18.x）、`ls /sys/kernel/btf/vmlinux`（BTF）、
  LuCI：网络→Airoha NPU 状态、网络→FTTR、网络→PON（光模块卡片）、
  服务→Honk（Doona）

## 已知上游问题（非本仓库能解决）
- OLT 下行光口散热（需风扇），NPU 卸载引擎挂载问题（上游 PR 已修部分）
