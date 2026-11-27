# LuCI 前端改动"看似没生效"的根因与修复

## 现象
固件里 PON/FTTR 的 JS 确实是改造版（md5 验证过），但浏览器里看到的还是旧界面。强刷（Ctrl+F5）也没用。

## 根因
LuCI 通过 URL 版本戳给浏览器缓存静态资源：

```
/luci-static/resources/luci.js?v=<版本戳>
```

版本戳来自 `/usr/share/ucode/luci/template/header.ut`：
```
luci.js?v=26.328.10257~6839c87-<pkgs_update_time>
```

其中 `pkgs_update_time` 由 `/usr/share/ucode/luci/runtime.uc` 计算：
```js
self.env.pkgs_update_time = stat('/lib/apk/db/installed')?.mtime
                         ?? stat('/usr/lib/opkg/status')?.mtime ?? 0;
```

**问题**：保留配置 sysupgrade 时，`/lib/apk/db/installed` 的 mtime 往往不变 →
版本戳不变 → 浏览器认为资源未变，继续用缓存的旧 `pon/config.js`、`pon/status.js` 等模块。
Ctrl+F5 只刷主 HTML，LuCI 动态 `require` 的模块缓存仍在。

## 判定方法
1. 确认固件是新版：`md5sum /usr/sbin/fttrd` / `md5sum /www/luci-static/resources/view/pon/config.js`
2. 确认 luci.js 版本戳：`curl -s http://<路由器>/ | grep -o 'luci.js?v=[^"]*'`
   - 如果刷新固件前后版本戳一样，就是缓存问题。

## 修复
`files/etc/uci-defaults/12-luci-cache-bust`：首启 touch 包数据库，强制 mtime 更新。

```sh
touch /lib/apk/db/installed
touch /usr/lib/opkg/status
```

uci-defaults 每次刷机（含保留配置升级）都执行一次，所以版本戳必然变化，浏览器重载所有 LuCI 资源。

## 验证规则（以后每次改前端都要做）
- 不能只验证"镜像里文件在不在"——还要验证**资源版本戳随构建变化**。
- 交付前对比新旧固件的 `luci.js` md5 与 header.ut 版本戳前缀；若相同，必须带 cache-bust 脚本。
