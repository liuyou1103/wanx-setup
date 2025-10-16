# 🚀 万象平台一键安装脚本仓库

**一键部署万象平台所需的基础软件和服务，简化开发者和用户的安装流程。**

---

## 📁 仓库目录结构

```bash
├── developer/          # 开发者专用脚本和配置
│   ├── baai_server_ceshi.conf    # 测试环境服务器配置
│   ├── baai_server_release.conf # 生产环境服务器配置
│   └── developer_x86_setup.bash # 开发者版 x86 架构一键安装脚本
├── user/                # 用户专用脚本（待补充）
└── README.md            # 本说明文件
```
---
## 🛠️ 开发者安装指南
```bash
git clone git@github.com:liuyou1103/wanx-setup.git
cd wanx-setup/developer
./developer_x86_setup.bash
```
