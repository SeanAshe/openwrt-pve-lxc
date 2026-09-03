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
| 地址 | LAN 走 **DHCP 客户端**，向主路由要地址 |
| DHCP 服务 | 关闭，避免和主路由抢发地址 |
| 防火墙 | 单区域全部 ACCEPT，不做 NAT |
| 时区 | `Asia/Shanghai` / `CST-8` |
| 软件包 | `luci` `luci-ssl`，去掉 PPPoE |

把需要走旁路由的设备，网关（和可选 DNS）指到这台 OpenWrt 的 LAN 地址即可。

## 用 GitHub Actions 编译

1. 把本仓库推到 `main` 或 `master`。
2. 打开 **Actions**，允许工作流。
3. 运行 **Build OpenWrt PVE LXC**。
4. 结束后从 **Artifacts** 或 **Releases** 下载 tar.gz。

改 `configs/`、`files/`、`packages/` 或 workflow 推到默认分支也会自动编。

本地 Linux / WSL（不要在纯 Windows 上跑）：

```bash
sudo apt-get install -y build-essential gawk unzip wget python3 \
  libncurses-dev zlib1g-dev zstd rsync file gettext curl
bash scripts/build-imagebuilder.sh
```

## 在 PVE 上创建容器

把 tar.gz 放到 `/var/lib/vz/template/cache/`，或在数据存储的 **CT Templates** 里上传。必须用命令行创建（GUI 选不了 `unmanaged`）：

```bash
pct create 201 local:vztmpl/openwrt-25.12.5-x86-64-pve-lxc.tar.gz \
  --ostype unmanaged \
  --arch amd64 \
  --hostname openwrt \
  --cores 2 \
  --memory 256 \
  --swap 0 \
  --rootfs local-lvm:1 \
  --features nesting=1 \
  --unprivileged 0 \
  --net0 name=eth0,bridge=vmbr0
```

`scripts/pct-create.example.sh` 是同一套命令的可改模板。

```bash
pct start 201
pct exec 201 -- passwd
pct exec 201 -- ip -4 addr show
```

LuCI 在 `https://<容器IP>/`。浏览器会提示自签证书，属正常。

## 改成静态 IP

编辑 `files/etc/uci-defaults/99-bypass-router` 顶部：

```sh
LAN_PROTO="static"
LAN_IP="192.168.1.2"
LAN_NETMASK="255.255.255.0"
LAN_GATEWAY="192.168.1.1"
LAN_DNS="192.168.1.1"
```

改完重新跑 Actions。已经在跑的容器里也可以：

```bash
pct exec 201 -- sh -c "uci set network.lan.proto=static
uci set network.lan.ipaddr=192.168.1.2
uci set network.lan.netmask=255.255.255.0
uci set network.lan.gateway=192.168.1.1
uci set network.lan.dns=192.168.1.1
uci commit network
/etc/init.d/network restart"
```

## 加软件包

改 `configs/x86_64.env` 里的 `PACKAGES`。减包在名字前加 `-`。额外 `.ipk` 放到 `packages/`。

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
configs/x86_64.env                 # 版本、校验和、软件包
files/etc/uci-defaults/            # 首次启动：旁路由单网卡
packages/                          # 可选本地 ipk
scripts/build-imagebuilder.sh      # 本地 ImageBuilder
scripts/pack-lxc.sh                # 整理成 PVE 模板名
scripts/pct-create.example.sh      # 宿主机创建容器示例
.github/workflows/build.yml        # GitHub Actions
```
