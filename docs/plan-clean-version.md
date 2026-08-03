# 纯净版逐层测试计划

## 可能的失败原因（待逐一排除）

| # | 嫌疑 | 理由 |
|---|---|---|
| A | 二进制补丁（openwrt→h3c_） | f2 带 null padding，服务器可能拒识 |
| B | DNS 劫持到 h3crglg | 非 H3C 身份连 H3C 端点可能被拒 |
| C | guardian 退出码 1 | 二进制依赖 guardian，死了就离线 |
| D | 环境变量伪装 | UU_MODEL/UU_VENDOR 与二进制不一致 |
| E | mgmt_proxy 干扰 | HTTP 400→200 改写破坏了协议 |
| F | uu.conf 配置缺失/多余 | 多余 key 或缺失 version |
| G | 网络/防火墙 | iptables/nftables 规则冲突 |

## 测试层级（从零开始叠加）

### L0：纯净二进制（基线）
- 无补丁，无劫持，无代理，无伪装
- 二进制以原始 openwrt 身份直连 UU 服务器
- **预期**：能注册、能加速（或至少能联网）
- **若失败**：问题在二进制本身或运行环境

### L1：加二进制补丁
- Dockerfile 补丁：openwrt→h3c-nx30pro
- 仍无劫持，直接连 rglg.uu.163.com
- **若失败**：补丁破坏了二进制功能

### L2：加 DNS 劫持
- /etc/hosts: rglg.uu.163.com → h3crglg.uu.163.com
- 补丁后 H3C 身份连 H3C 端点
- **若失败**：H3C 端点拒绝我们的身份

### L3：加环境变量伪装
- UU_MODEL, UU_VENDOR, UU_PLUGIN_VESION 等
- **若失败**：env 与补丁不一致

### L4：加 mgmt_proxy
- 代理 16363→16365, 14554→14555
- **若失败**：代理破坏了绑定协议

### L5：加 MITM
- protobuf 修改 (f2, f6, FullRegister 精简)
- **若失败**：篡改导致服务端下发异常配置

## 文件改动

### 重构 start.sh
- 所有功能做成 `UU_FEATURE_*=1` 开关
- 默认全部关闭（纯净模式）
- 清晰的 section 分隔

### 重构 docker-compose.yml
- 对应开关集中管理
- 默认全部注释掉（纯净模式）

### Dockerfile
- 补丁是编译时行为，需配合开关跳过
- L0 使用未补丁的二进制；L1+ 开启补丁

---

创建日期：2026-08-03
