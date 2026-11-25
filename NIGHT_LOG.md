# 2026-11-24 夜间/上午工作日志

## 最终可用固件（2026-11-25 晚上）
**Release v30**（构建 #30，green，当前唯一版本）：
https://github.com/likz0421/an7581-ci/releases/tag/v30

构建 #30 全部步骤 success（Build / Verify / Upload / Create Release），含本轮三层整改：
出厂默认值（IP/WiFi）、FTTR 前端 bundle 重建、FTTR 后端接口数 UCI 可配置。
两个 HM2004 itb 附件齐全（sysupgrade 36.2MB + recovery 30.1MB），artifact an7581-run-30 70.7MB。

## 2026-11-25 晚上整改：出厂默认值 + FTTR 前后端
用户反馈：IP 仍是 192.168.1.1、WiFi 未改、FTTR 前端"优化"没进固件、16 个 fttr 口太多想自定义。

### 根因
1. IP/WiFi：旧脚本靠精确匹配 `192.168.1.1`/`OpenWrt` 判断，但新版 PonWrt 的 board.d
   在启动较晚阶段才生成网络/WiFi 配置，判断时机和值都对不上 → 永远不触发。
2. FTTR 前端美化：CI 只拉 package 分支（编译好的 bundle），之前的修复改在 main 源码分支，
   从未重新构建推 package → 固件里根本没有修复。
3. fttr 口：H3C 后端 setup_bridge 把 16 个下游口全桥进 br-lan，前端无数量配置。

### 修复（全部落地并推送，构建 #30 验证 through）
- **层1 默认值**：`files/etc/uci-defaults/10-hanzi-defaults` + `files/etc/rc.local` 改为
  "首启标记"机制（`/etc/hanzi-defaults-applied`）：全新刷机首启无条件写 LAN 10.1.1.1、
  DHCP .2 起 36h、WiFi hanzi/hanziwawa，打标记；之后开机/保留配置升级不再动用户设置。
  不再依赖出厂字符串判断。sh -n 语法检查通过。（commit f503385）
- **层2 前端**：本地搭前端构建环境（clone + npm install + rsbuild build 成功），
  源码改动推 main、重新构建的 9 个 bundle 推 package 分支（luci-app-fttr）。
- **层3 FTTR 接口数**：
  - 后端 fork `likz0421/openwrt-fttr` 建 `an7581-custom` 分支（4c4cfe0）：
    新增 `setup_bridge_limited()` + `configured_lan_ports()`，读 UCI `fttr.h3c.lan_ports`
    （1~16，默认16）只桥接前 N 个，其余从 br-lan 移除并 down。
  - 前端 config 页加 "FTTR LAN port count" 输入框（1~16）+ 保存/生效状态显示，bundle 已推 package。
  - `scripts/configure.sh` 的 fttr feed 指向 fork 的 an7581-custom 分支（commit 2608eff）。
- 用法：网页 FTTR→配置→基本 改端口数后 Restart；或
  `uci set fttr.h3c.lan_ports=4 && uci commit fttr && /etc/init.d/fttr restart`。不配置=保持16。

### 已知边界
- fttr netdev 本身由内核驱动按硬件槽位创建（16 个），未改内核驱动（避免交叉编译风险），
  故"设备"列表仍会看到 fttr 口；但 br-lan 里只保留设定的 N 个（截图2的核心痛点已解决）。
- 本机无 cargo，Rust 后端改动靠 CI 编译验证；#30 Build:success 证明编译通过。

### 交付验证（v30 固件二进制级，2026-11-25 晚）
解包 v30 sysupgrade.itb 的 squashfs rootfs（PySquashfsImage from_file offset），逐项确认：
- `/etc/rc.local`：含首启标记机制全文（10.1.1.1 / DHCP .2-36h / hanzi+hanziwawa / MARK=/etc/hanzi-defaults-applied）✓
- `/etc/uci-defaults/10-hanzi-defaults`：含双保险写入逻辑 ✓
- `/www/luci-static/resources/view/fttr/config.js`（85035 字符）：含 lan_ports / FTTR LAN port count /
  自动 `uci.add("fttr","h3c","h3c")` + `set lan_ports 16` ✓
- `/usr/sbin/fttrd`（7.4MB 二进制）：含 `lan_ports` 字符串（后端读 UCI 的 option 名）✓
- `/etc/config/fttr`：含 H3C 端口数说明与 `# config h3c` 示例 ✓
结论：三层改动全部真正打进 v30 固件，非仅源码分支。

## 2026-11-25 晚：FTTR 前后端 bug 修复（v30 实测反馈，在线增量升级）
用户 v30 实测：lan_ports=1 重启后 br-lan 只剩 1 fttr（后端生效✓），但报 3 个问题：
1. `unsupported section: h3c`（config_check 失败）— 后端 templates.rs section 白名单不含 h3c。修复：白名单+allowed+1~16 校验+business_canonical 排除。
2. 前端 `Saved/active 1/16·待重启` 误报 — basic.tsx 把 active 错算成 ONU 总数。修复：移除错误对比改准确说明；FiberHome 同类一并修。
3. `PPE counters: unavailable/invalid/overflowing` — ppe.rs 把空 bind 表误报成错误。修复：仅采样到 flow 数据无效才报错。
推送：后端 an7581-custom@8fb254e，前端 package@a4275e6/main@5c933a6。
在线升级（不重刷固件）：前端 config.js 自包含可直接 scp 覆盖（online-fix/frontend/config.js）；后端 apk 由新 workflow build-fttr-packages.yml 编译（run#1）。详见 online-fix/README.md。

旧记录（v26）见下方。

## 2026-11-25 下午整改：apk 产物校验误判
- 现象：#23 编译成功但 `Verify build outputs` 失败，报 required packages missing；
  实际 PonWrt master 用 apk，包名是 `honk-2026.11.24.2-r1.apk` 这种"包名-版本"格式，
  校验却只匹配 `honk_*.ipk`。
- 修复：`build-an7581.yml` 的 check() 同时兼容 `name_version.ipk`、
  `name_version.apk`、`name-version.apk`，并新增 HM2004 sysupgrade itb 硬检查，
  避免"构建成功但没固件"仍发版（commit b5eb692）。
- 同步修正 README 中 uci-defaults 生效时机的描述（首启执行，不是每次启动）。
- #25 因仍用旧校验规则被提前取消；#27 为 push + dispatch 重复触发，也已取消；
  #26 一次通过。

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
   以后每次成功构建自动创建 Release（附 .itb 镜像）。
7. **诊断通道**：失败时日志尾部自动写 check-run 注解 + diagnostics/ 提交
   （Actions 日志 403 时也能看错误）。

## 状态
- 构建 #26：全步骤成功，artifact `an7581-run-26` 可下载，Release v26 已发
- 网络已恢复，GitHub API 可正常读取构建/Release
- 仓库只保留 #26 一条成功构建记录和 v26 一个 Release

## 刷机
- HM2004 是 FIT 镜像，取 `*-h3c_hm2004-du-squashfs-sysupgrade.itb`（已刷 PonWrt）
  或 `*-h3c_hm2004-du-initramfs-recovery.itb`（救援）；首刷用 an758x-stock2ubi
- 想让 LAN 10.1.1.1 / DHCP .2 起 36h / WiFi hanzi 生效，刷机时不要保留配置（sysupgrade -n）
- 验证：`uname -r`（6.18.x）、`ls /sys/kernel/btf/vmlinux`（BTF）、
  LuCI：网络→Airoha NPU 状态、网络→FTTR、网络→PON（光模块卡片）、
  服务→Honk（Doona）

## 已知上游问题（非本仓库能解决）
- OLT 下行光口散热（需风扇），NPU 卸载引擎挂载问题（上游 PR 已修部分）
