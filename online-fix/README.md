# FTTR 前后端修复 — 在线增量升级包（不重刷固件）

本目录用于在**当前 OpenWrt（v30 及以后）上直接在线升级验证** FTTR 前后端修复，无需重刷完整固件。

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

后端 fttrd 是编译后的二进制，需升级 apk。GitHub Actions workflow `build-fttr-packages`
（run id `45612411796`）正在编译。完成后从该 run 的 artifact `fttr-packages` 下载
`openwrt-fttr-*.apk`，传到设备：

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

## 提交记录

- 前端 `likz0421/luci-app-fttr`
  - main @ `3884317`：`fix(fttr ui): filter downstream ports by lan_ports; replace G6 topology with lightweight status-based view`
  - package @ `9eec61a`：9 个 bundle（config/index/topology 等）
- 后端 fork `likz0421/openwrt-fttr` 分支 `an7581-custom` @ `8fb254e`（config_check h3c + PPE counters）
- CI 单包 workflow `.github/workflows/build-fttr-packages.yml`（commit `f76c3e0`）
