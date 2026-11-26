#!/bin/bash
# PonWrt AN7581 configure: kernel options + feeds + .config + defconfig
# Usage: CI_ROOT=<this-repo checkout> bash scripts/configure.sh <ponwrt_ref> <with_fttr> <pon_userspace_pr16>
set -euo pipefail

REF="${1:-master}"
WITH_FTTR="${2:-true}"
PR16="${3:-true}"
CI_ROOT="${CI_ROOT:?CI_ROOT (repo checkout) must be set}"

step() { echo; echo "########## [configure] $* ##########"; }

step "1/6 pin PonWrt ref ($REF)"
cd ponwrt
if [ "$REF" != "master" ]; then
  git fetch --depth=1 origin "$REF"
  git checkout "$REF"
fi
git log -1 --oneline

step "2/6 patch kernel config (honk eBPF: BTF/cgroup/TC-bpf/ftrace)"
KCFG="target/linux/airoha/an7581/config-6.18"
if [ -f "$KCFG" ]; then
  for opt in CONFIG_DEBUG_INFO_BTF CONFIG_CGROUP_BPF CONFIG_NET_CLS_ACT CONFIG_NET_XGRESS \
             CONFIG_FUNCTION_TRACER CONFIG_DYNAMIC_FTRACE; do
    sed -i "/^${opt}=/d;/^# ${opt} is not set/d" "$KCFG"
  done
  cat >> "$KCFG" <<'EOF'
CONFIG_DEBUG_INFO_BTF=y
CONFIG_CGROUP_BPF=y
CONFIG_NET_CLS_ACT=y
CONFIG_NET_XGRESS=y
CONFIG_FUNCTION_TRACER=y
CONFIG_DYNAMIC_FTRACE=y
EOF
  echo "[kernel] patched $KCFG"
else
  echo "[kernel] WARNING: $KCFG not found; honk may fail to start (no BTF)"
fi

step "3/6 append feeds (honk/fttr/PR16)"
# NOTE: OpenWrt feeds parser requires the feed name to be \w+ (no dashes).
echo "src-git honk https://github.com/kenzok8/openwrt-honk.git" >> feeds.conf.default
# video/telephony feed 上游有 kconfig 递归依赖 bug（2026-11-25 起），且 OLT 固件不需要
sed -i 's|^src-git video .*|# &  # disabled: upstream qt5 kconfig recursive dependency|' feeds.conf.default
sed -i 's|^src-git telephony .*|# &  # disabled: not needed for OLT firmware (also cuts build time)|' feeds.conf.default
if [ "$WITH_FTTR" = "true" ]; then
  # Use our fork's an7581-custom branch: adds UCI-configurable br-lan fttr port
  # count (fttr.h3c.lan_ports) on top of upstream LazuliKao/openwrt-fttr.
  echo "src-git fttr https://github.com/likz0421/openwrt-fttr.git;an7581-custom" >> feeds.conf.default
  echo "[feeds] fttr enabled (our fork @an7581-custom: configurable lan_ports; frontend from local package clone)"
fi
if [ "$PR16" = "true" ]; then
  # feeds.conf syntax: <url>[;<ref>]  (branch refs use ';')
  sed -i 's|^src-git pon_userspace .*|src-git pon_userspace https://github.com/DenzelVincent/openwrt-pon-userspace.git;main|' feeds.conf.default
  echo "[feeds] pon_userspace -> DenzelVincent fork (PR#16 head)"
fi
echo "[feeds] feeds.conf.default:"
grep -E '^(src-git|src-link)' feeds.conf.default || true

step "4/6 apply base config + additions"
cp configs/an7581.config .config
cat "$CI_ROOT/.config.additions" >> .config
if [ "$WITH_FTTR" = "true" ] && [ -f "$CI_ROOT/.config.fttr" ]; then
  cat "$CI_ROOT/.config.fttr" >> .config
  echo "[config] .config.fttr applied"
fi
tail -n 20 .config

step "5/6 feeds update + install + local apps"
./scripts/feeds update -a
# FTTR 后端 feed 布局修正：LazuliKao/openwrt-fttr 的包目录在仓库根，
# OpenWrt feed 只认 <feed>/package/*/Makefile → 套一层 package/
if [ -d feeds/fttr ]; then
  cd feeds/fttr
  mkdir -p package
  for d in fttr h3c-fmcs h3c-fmcs-firmware fiberhome-fsl; do
    [ -d "$d" ] && mv "$d" package/
  done
  cd - >/dev/null
  echo "[feeds] fttr layout wrapped: $(ls feeds/fttr/package | tr '\n' ' ')"
  # 上游 fttr Makefile 的 Package/openwrt-fttr/config 块内 "depends on PACKAGE_openwrt-fttr"
  # 与 DEPENDS 里的 "+FTTR_PLATFORM_*:dep" 形成 kconfig 循环依赖（上游 bug），
  # 去掉 config 侧那半边依赖即可（kconfig 只报循环，不影响功能）
  if [ -f feeds/fttr/package/fttr/Makefile ]; then
    sed -i 's/^\([[:space:]]*\)depends on PACKAGE_openwrt-fttr$/\1# patched-out: cycle with DEPENDS +FTTR_PLATFORM_*:dep/' \
      feeds/fttr/package/fttr/Makefile
    echo "[feeds] fttr Makefile kconfig cycle patched: $(grep -c 'patched-out: cycle' feeds/fttr/package/fttr/Makefile || true) lines"
  fi
  # 关键：索引已在 update 时按旧布局生成，移动后必须重建，否则 install 装的是坏链接
  ./scripts/feeds update -i
  echo "[feeds] feed indexes rebuilt"
fi
./scripts/feeds install -a
# 上游 feed 的 fwknop 有 kconfig 递归依赖 bug（2026-11-25 起），
# 会让 defconfig 中途报错、后续所有包被丢弃；OLT 固件不需要，移除
# 注意：feeds install 建的是符号链接，find 必须同时匹配 -type l
for p in $(find package/feeds -maxdepth 2 \( -name 'fwknop*' -o -name 'luci-app-fwknopd*' \) \( -type d -o -type l \) 2>/dev/null); do
  rm -rf "$p" && echo "[feeds] removed broken package: $p"
done
# FTTR 前端：fork 的 package 分支根目录就是包本身，直接拷进 package/（不用 feed）
if [ "$WITH_FTTR" = "true" ] && [ ! -d package/luci-app-fttr ]; then
  git clone --depth=1 -b package https://github.com/likz0421/luci-app-fttr.git /tmp/fttrui-src
  cp -r /tmp/fttrui-src package/luci-app-fttr
  rm -rf /tmp/fttrui-src package/luci-app-fttr/.git
  echo "[fttr-ui] luci-app-fttr staged into package/ ($(ls package/luci-app-fttr | tr '\n' ' '))"
fi
# 芯片状态 App：DenzelVincent/luci-app-airoha-npu（rchen14b 的中文增强 fork，v1.3.1）
# 仓库内包目录为 luci-app-airoha-npu/（Makefile+htdocs+po+root）
if [ ! -d package/luci-app-airoha-npu ]; then
  git clone --depth=1 https://github.com/DenzelVincent/luci-app-airoha-npu.git /tmp/luci-app-airoha-npu-src
  cp -r /tmp/luci-app-airoha-npu-src/luci-app-airoha-npu package/luci-app-airoha-npu
  rm -rf /tmp/luci-app-airoha-npu-src
  echo "[npu] luci-app-airoha-npu (DenzelVincent v1.3.1) staged into package/"
fi
# 主题：用 anothaDev/luci-theme-vantage 替换默认的 argon。
# 仓库内包目录为 luci-theme-vantage/（Makefile + htdocs + ucode + po + root），ucode 模板与当前 LuCI 同构。
if [ ! -d package/luci-theme-vantage ]; then
  git clone --depth=1 https://github.com/anothaDev/luci-theme-vantage.git /tmp/luci-theme-vantage-src
  cp -r /tmp/luci-theme-vantage-src/luci-theme-vantage package/luci-theme-vantage
  rm -rf /tmp/luci-theme-vantage-src
  echo "[theme] luci-theme-vantage staged into package/"
fi
# 本地包依赖修正：luci-app-fttr 依赖 openwrt-fttr（Package 定义名，正确）无需改；
# 打印确认 fttr 包确实可被扫到
echo "[feeds] fttr feed package dirs:"
find feeds/fttr/package -maxdepth 2 -name Makefile 2>/dev/null | sort || true

step "6/6 make defconfig"
# 烧入自定义默认值（files/ 覆盖层：LAN 10.1.1.1 / DHCP 从 .2 起顺序分配 36h 租约 / WiFi hanzi）
rm -rf files
cp -rf "$CI_ROOT/files" files
echo "[files] custom defaults staged:"
find files -type f | sort

# defconfig 自愈：上游 feed 偶发 kconfig 递归依赖错误（今天 video qt5、packages fwknop
# 都是这样），会让后续所有包被丢弃。检测到错误就摘掉出问题的包目录并重试。
attempt=0
while :; do
  attempt=$((attempt + 1))
  make defconfig > /tmp/defconfig.log 2>&1 || true
  if ! grep -q 'recursive dependency detected' /tmp/defconfig.log; then
    echo "[defconfig] clean (attempt $attempt)"
    break
  fi
  echo "[defconfig] kconfig error (attempt $attempt):"
  sed -n '/recursive dependency detected/,/For a resolution/p' /tmp/defconfig.log | head -12
  if [ "$attempt" -ge 4 ]; then
    echo "[defconfig] ERROR: still failing after $attempt attempts"
    tail -40 /tmp/defconfig.log
    exit 1
  fi
  bad=$(sed -n '/recursive dependency detected/,/For a resolution/p' /tmp/defconfig.log \
        | grep -oE 'PACKAGE_[A-Za-z0-9_.-]+' | sed 's/^PACKAGE_//' | sort -u)
  removed=0
  for name in $bad; do
    for d in $(find package/feeds -maxdepth 2 \( -name "${name}*" \) \( -type d -o -type l \) 2>/dev/null); do
      rm -rf "$d"
      echo "[defconfig] removed offending package dir: $d"
      removed=1
    done
  done
  if [ "$removed" = "0" ]; then
    echo "[defconfig] ERROR: cannot map offending symbols to package dirs"
    tail -40 /tmp/defconfig.log
    exit 1
  fi
done
grep -E '^(CONFIG_|# CONFIG_)' /tmp/defconfig.log | head -5 || true
echo
echo "########## [configure] selections ##########"
grep -E '^CONFIG_PACKAGE_(honk|luci-app-honk|luci-app-airoha-npu|openwrt-fttr|kmod-h3c-fmcs|h3c-fmcs-firmware|luci-app-fttr|luci-app-passwall)=' .config || true
# 关键校验 1：H3C 设备必须选上，否则构建出的固件里没有 HM2004 镜像
if ! grep -qE '^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_h3c_hm2004-du=y$' .config; then
  echo "[configure] ERROR: h3c_hm2004-du device not selected in .config"; exit 1
fi
# 关键校验 2：必须选中的软件包，defconfig 静默丢弃任何一项都说明 feed/布局有问题，直接失败
REQ_PKGS="CONFIG_PACKAGE_honk CONFIG_PACKAGE_luci-app-honk CONFIG_PACKAGE_luci-app-airoha-npu CONFIG_PACKAGE_luci-app-pon CONFIG_PACKAGE_luci-theme-vantage"
if [ "$WITH_FTTR" = "true" ]; then
  REQ_PKGS="$REQ_PKGS CONFIG_PACKAGE_openwrt-fttr CONFIG_PACKAGE_kmod-h3c-fmcs CONFIG_PACKAGE_h3c-fmcs-firmware CONFIG_PACKAGE_luci-app-fttr"
fi
echo "[verify] required packages after defconfig:"
fail=0
for p in $REQ_PKGS; do
  if grep -q "^${p}=y$" .config; then
    echo "  ok   $p"
  else
    echo "  MISS $p"; fail=1
  fi
done
if [ "$fail" = "1" ]; then
  echo "[configure] ERROR: required packages missing after defconfig (check feed layout / package names)"
  exit 1
fi
echo "[npu] busybox devmem:"; grep -E 'CONFIG_BUSYBOX_CONFIG_DEVMEM' .config || true
echo "[kernel] BTF line:"
grep -E 'CONFIG_DEBUG_INFO_BTF' target/linux/airoha/an7581/config-6.18 || true
echo "[configure] OK"
