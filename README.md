# OpenWrt PVE LXC（官方 25.12 · 旁路由单网卡）

用 GitHub Actions 调用官方 [ImageBuilder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder) 生成 **x86-64 `rootfs.tar.gz`**，供 Proxmox VE 以 LXC 容器跑 OpenWrt 旁路由。

当前版本：**OpenWrt 25.12.5**（`configs/x86_64.env`）。

远程仓库：<https://github.com/SeanAshe/openwrt-pve-lxc>

## 产物

Actions 打出：

```text
openwrt-25.12.5-x86-64-pve-lxc.tar.gz
openwrt-25.12.5-x86-64-pve-lxc.tar.gz.sha256
```

这是 **rootfs**，不是带内核的 combined 镜像。LXC 用 PVE 宿主内核，不要拿 `*-combined*.img` 去 `pct create`。

首次启动后会执行 `files/etc/uci-defaults/99-bypass-router`：

| 项 | 行为 |
|---|---|
| 网卡 | 只用 `eth0`（默认 `br-lan`），删除 WAN / WAN6 |
| 地址 | LAN 静态 **192.168.7.3/24** |
| 网关 / DNS | **192.168.7.1** |
| DHCP 服务 | 关闭，避免和主路由抢发地址 |
| 防火墙 | 单区域全部 ACCEPT，不做 NAT |
| 时区 | `Asia/Shanghai` / `CST-8` |
| 软件包 | `luci` `luci-ssl`；**简体中文**；**UPnP**（`miniupnpd-nftables`）；包管理是 **apk**（不是 opkg）；不含 PPP |

把需要走旁路由的设备，网关（和可选 DNS）指到 `192.168.7.3`。LuCI：`https://192.168.7.3/`。

## 用 GitHub Actions 编译

只在手动触发时编译，推送代码不会自动跑。

1. 打开仓库 **Actions** → **Build OpenWrt PVE LXC**。
2. 点 **Run workflow**。需要发 Release 时勾选 `create_release`（默认已勾选）。
3. 结束后从 **Artifacts** 或 **Releases** 下载 tar.gz。

本地 Linux / WSL（不要在纯 Windows 上跑）：

```bash
sudo apt-get install -y build-essential gawk unzip wget python3 \
  libncurses-dev zlib1g-dev zstd rsync file gettext curl
bash scripts/build-imagebuilder.sh
```

## 在 PVE 上创建容器

把 tar.gz 放到 `/var/lib/vz/template/cache/`，或在数据存储的 **CT Templates** 里上传。必须用命令行创建（GUI 选不了 `unmanaged`）：

```bash
pct create 100 local:vztmpl/openwrt-25.12.5-x86-64-pve-lxc.tar.gz \
  --ostype unmanaged \
  --arch amd64 \
  --hostname Openwrt \
  --cores 1 \
  --memory 1024 \
  --swap 0 \
  --rootfs local-lvm:1 \
  --features nesting=1 \
  --unprivileged 0 \
  --net0 name=eth0,bridge=vmbr0
```

```
arch: amd64
cores: 1
features: nesting=1
hostname: Openwrt
memory: 1024
net0: name=eth0,bridge=vmbr0,firewall=1,gw=192.167.7.3,hwaddr=BC:24:11:8A:BA:8D,ip=192.168.7.13/24,ip6=dhcp,type=veth
onboot: 1
ostype: unmanaged
rootfs: local-lvm:vm-100-disk-0,size=1G
startup: order=0
swap: 0
tags: base
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
lxc.cgroup2.cpuset.cpus: 12
```

```bash
pct start 201
pct exec 201 -- passwd
pct exec 201 -- ip -4 addr show
```

LuCI 在 `https://192.168.7.3/`。浏览器会提示自签证书，属正常。

改地址时编辑 `files/etc/uci-defaults/99-bypass-router` 顶部的 `LAN_IP` / `LAN_GATEWAY` / `LAN_DNS`，然后重新编译。

## 加软件包

OpenWrt 25.12 用 **apk**，不要再用 `opkg`。容器里：

```sh
apk update
apk add <包名>
apk search luci-app-
```

编进镜像：官方包写在 `configs/packages.list`。OpenClash 和 Argon 不在官方源，**不要**放进 ImageBuilder 的 `packages/`。构建时从 GitHub Release 下载 `.apk` 拷进镜像，容器**首次启动**时用官方文档里的 `apk add --allow-untrusted` 安装。

## Tailscale

镜像只按 [GuNanOvO APK 安装指南](https://gunanovo.github.io/openwrt-tailscale/zh/guide/apk-setup.html) **添加软件源**，不预装软件包：

- 公钥：`/etc/apk/keys/gunanovo@github.io.pub`
- 软件源：`/etc/apk/repositories.d/customfeeds.list`（x86_64）

需要时在容器里安装：

```sh
apk update
apk add tailscale
tailscale up --accept-dns=false --hostname=openwrt
```

Tailscale 需要 `/dev/net/tun`。特权容器一般已有；若没有，在 **PVE 宿主机** 执行 `modprobe tun`。

LXC **加载不了 OpenWrt 的 kmod**。TPROXY / WireGuard 等要在 **PVE 宿主机** 装模块，例如：

```bash
echo xt_TPROXY >> /etc/modules-load.d/openwrt-lxc.conf
modprobe xt_TPROXY
```

非特权容器还要在 `/etc/pve/lxc/<CTID>.conf` 里挂 `/dev/net/tun`。本模板默认特权容器，省掉这一步。

## 升级 25.12.x

1. 打开 <https://downloads.openwrt.org/releases/> 看最新 `25.12.*`。
2. 改 `configs/x86_64.env` 的 `OPENWRT_VERSION`。
3. 从该版本 `targets/x86/64/sha256sums` 里复制 `openwrt-imagebuilder-*-x86-64.Linux-x86_64.tar.zst` 的哈希，写到 `IMAGEBUILDER_SHA256`。
4. 同步改 README 和 `scripts/pct-create.example.sh` 里的文件名。

## 目录

```text
configs/x86_64.env                 # 版本、校验和
configs/packages.list              # 官方软件包列表
files/etc/uci-defaults/            # 首次启动：旁路由单网卡
files/etc/apk/                     # GuNanOvO Tailscale 公钥与软件源
scripts/build-imagebuilder.sh      # 本地 ImageBuilder
scripts/download-luci-extras.sh    # 下载 OpenClash / Argon apk
files/etc/uci-defaults/98-install-luci-extras  # 首次启动安装上述 apk
scripts/pack-lxc.sh                # 整理成 PVE 模板名
scripts/pct-create.example.sh      # 宿主机创建容器示例
.github/workflows/build.yml        # GitHub Actions
```
