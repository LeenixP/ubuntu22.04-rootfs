# Ubuntu for TSPI-M1-RK3566 (Linux 5.10)

#### 介绍
为 `TSPI-M1-RK3566` 开发板定制的 Ubuntu 22.04.5 LTS系统，基于Linux 5.10.209内核。支持桌面版(xfce)和服务器版两种构建方式。

#### 软件架构

```tree
构建脚本关系图
├── clean-build.sh       # 清理构建环境
├── mk-base-ubuntu.sh    # 生成基础rootfs
├── mk-ubuntu-rootfs.sh  # 安装硬件驱动和软件包
├── mk-image.sh          # 生成可烧录镜像
├── ch-mount.sh          # 挂载/卸载工具
└── post-build.sh        # 镜像后处理脚本
```

#### 安装教程

**环境要求**
- Ubuntu 22.04 LTS 主机环境
- 网络环境确保正常
- 存储空间：至少 `50GB` 可用空间
- 宿主机环境依赖需要安装！具体步骤在下面的 `1. 检查宿主机环境`

**构建步骤**

> 【注意】
> 1. 请确保网络环境良好
> 2. 请确保已经满足所有所主机所需要的环境依赖与软件包等
> 3. 全程都在`ubuntu目录`下操作

1. 检查宿主机环境并安装设置依赖
```bash
sudo apt update && sudo apt full-upgrade && \
sudo ./host_check.sh && sudo pip3 install pyelftools && \
sudo ln -sf /usr/bin/python3 /usr/bin/python && \
sudo sed -i -e '/\%sudo/ c \%sudo ALL=(ALL) NOPASSWD: ALL' /etc/sudoers && \
sudo usermod -a -G sudo $USER && \
exec su - $USER
```

2. 选择构建类型（桌面版/服务器版）：
```bash
# 桌面版
GUI=desktop ./mk-base-ubuntu.sh && \
GUI=desktop ./mk-ubuntu-rootfs.sh && \
./mk-image.sh

# 服务器版
GUI=console ./mk-base-ubuntu.sh && \
GUI=console ./mk-ubuntu-rootfs.sh && \
./mk-image.sh
```

3. 最后会在当前`ubuntu目录`生成 `ubuntu-jammy.img` 镜像文件, 烧录到对应的`rootfs.img`地址即可~

#### 其他

**清理构建**
```bash
sudo ./clean-build.sh
```