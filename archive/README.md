# 存档 — 历史方案与可复用组件

## 身份伪装两层机制（当前架构）

```
┌─────────────────────────────────────────────┐
│ L1: 二进制补丁（start.sh 运行时 dd）          │
│   修改 .rodata 字符串：                        │
│   "openwrt" → "h3c_"      (OS 标识)          │
│   "OpenWrt" → "NX30Pro"   (设备名)            │
│   "openwrt-x86_64" → "h3c-nx30pro" (平台)    │
│   影响：二进制自己报告的身份、文件输出          │
├─────────────────────────────────────────────┤
│ L5: MITM (uu_mitm_mod.py, Windows 运行)       │
│   修改 protobuf：                              │
│   f2: "h3c_\x00..." → "h3c"  (去 null)       │
│   f6: 版本号替换                               │
│   FullRegister: 11 字段 → 3 字段               │
│   RegisterResp: "not found" → "not bound"     │
│   影响：服务器看到的 protobuf 消息              │
└─────────────────────────────────────────────┘
```

两层解决不同问题，不是重复：
- 补丁改"二进制自己认为的身份"（影响本地行为）
- MITM 改"服务器收到的身份"（影响网络协议）

## 可复用组件

| 组件 | 路径 | 用途 |
|---|---|---|
| MITM 代理 | `tools/uu_mitm_mod.py` | TLS 中间人，修改 protobuf |
| 管理代理 | `tools/uu_mgmt_proxy.py` | TCP 代理 16363/14554，400→200 |
| uuclearnat | `scripts/uuclearnat.sh` | 加速 NAT 伴侣，FIFO IPC |
| NX30Pro 参考 | `bin/NX30Pro_v14.4.20/` | 真机 uu.conf + 二进制 |

## 测试计划

见 `docs/plan-clean-version.md`
