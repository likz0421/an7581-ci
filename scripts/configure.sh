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
if [ "$WITH_FTTR" = "true" ]; then
  echo "src-git fttr https://github.com/LazuliKao/openwrt-fttr.git" >> feeds.conf.default
  echo "src-git fttrui https://github.com/likz0421/luci-app-fttr.git;package" >> feeds.conf.default
  echo "[feeds] fttr + fttrui (fork;package) enabled"
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

step "5/6 feeds update + install + NPU app"
./scripts/feeds update -a
./scripts/feeds install -a
# 芯片状态 App：rchen14b/luci-app-airoha-npu（repo 根即包 Makefile，克隆到 package/ 下）
if [ ! -d package/luci-app-airoha-npu ]; then
  git clone --depth=1 https://github.com/rchen14b/luci-app-airoha-npu.git package/luci-app-airoha-npu
  echo "[npu] luci-app-airoha-npu cloned into package/"
fi

step "6/6 make defconfig"
make defconfig
echo
echo "########## [configure] selections ##########"
grep -E '^CONFIG_PACKAGE_(honk|luci-app-honk|luci-app-airoha-npu|openwrt-fttr|kmod-h3c-fmcs|h3c-fmcs-firmware|luci-app-fttr|luci-app-passwall)=' .config || true
echo "[device] h3c_hm2004-du:"
grep -E 'CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_h3c_hm2004-du=' .config || true
# 关键校验：H3C 设备必须选上，否则构建出的固件里没有 HM2004 镜像
if ! grep -qE '^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_h3c_hm2004-du=y$' .config; then
  echo "[configure] ERROR: h3c_hm2004-du device not selected in .config"; exit 1
fi
echo "[npu] busybox devmem:"; grep -E 'CONFIG_BUSYBOX_CONFIG_DEVMEM' .config || true
echo "[kernel] BTF line:"
grep -E 'CONFIG_DEBUG_INFO_BTF' target/linux/airoha/an7581/config-6.18 || true
echo "[configure] OK"
