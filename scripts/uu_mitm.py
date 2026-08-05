#!/usr/bin/env python3
"""
uu_mitm.py — 容器内 TLS MITM，注入 H3C NX30Pro 身份参数

通过 /etc/hosts 劫持 rglg.uu.163.com → 127.0.0.1:16000，
拦截二进制 ↔ UU 服务器的 TLS 通信，修改 protobuf 消息伪装 H3C 身份。

仅劫持：rglg.uu.163.com（注册/身份服务）
不劫持：加速中继服务器 — 加速隧道流量直连不过 MITM

SN 来源：/tmp/uu/.sn（start.sh 从 br-lan MAC 生成，统一单点）
"""

import socket
import ssl
import struct
import sys
import os
import time
import threading
import select
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════
# 配置
# ═══════════════════════════════════════════════════════════════════════════

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 16000

# 真实 UU 注册服务器
REAL_HOST = '106.2.95.34'
REAL_PORT = 16000

# 证书路径（Docker 构建时生成）
CERT_DIR = Path('/opt/uu/certs')
CERT_FILE = CERT_DIR / 'mitm_cert.pem'
KEY_FILE  = CERT_DIR / 'mitm_key.pem'

# SN 统一来源
SN_FILE = Path('/tmp/uu/.sn')

# 目标 H3C NX30Pro 固件版本（注入到 Register f6）
TARGET_FW_VERSION = 'v14.4.20'

# ═══════════════════════════════════════════════════════════════════════════
# Protobuf 工具
# ═══════════════════════════════════════════════════════════════════════════

def pb_read_varint(data, pos=0):
    value = 0; shift = 0
    while pos < len(data):
        b = data[pos]; pos += 1
        value |= (b & 0x7F) << shift; shift += 7
        if not (b & 0x80): break
    return value, pos

def pb_parse(data):
    result = {}; pos = 0
    while pos < len(data):
        try: fh, pos = pb_read_varint(data, pos)
        except: break
        fn, wt = fh >> 3, fh & 0x07
        if wt == 0:
            v, pos = pb_read_varint(data, pos); result[fn] = v
        elif wt == 2:
            length, pos = pb_read_varint(data, pos)
            raw = data[pos:pos+length]; pos += length
            try:
                t = raw.decode('utf-8')
                result[fn] = t if all(32<=ord(c)<127 or c in '\n\r\t' for c in t) else f'<hex:{raw[:20].hex()}>'
            except: result[fn] = f'<hex:{raw[:20].hex()}>'
    return result

def pb_varint(v):
    r = []
    while v > 0x7F: r.append((v & 0x7F) | 0x80); v >>= 7
    r.append(v & 0x7F); return bytes(r)

def pb_str(fn, s):
    d = s.encode() if isinstance(s, str) else s
    return pb_varint((fn << 3) | 2) + pb_varint(len(d)) + d

def pb_int(fn, v):
    return pb_varint((fn << 3) | 0) + pb_varint(v)

def pb_replace_field_str(raw_pb, field_num, new_value):
    """替换 protobuf 中指定 field_num 的 string 值（按 field 结构解析，不靠字符串匹配）"""
    pos = 0
    while pos < len(raw_pb):
        fh, new_pos = pb_read_varint(raw_pb, pos)
        fn = fh >> 3; wt = fh & 0x07
        if fn == field_num and wt == 2:
            old_len, after_len_pos = pb_read_varint(raw_pb, new_pos)
            old_field_end = after_len_pos + old_len
            new_field = pb_str(field_num, new_value)
            return raw_pb[:pos] + new_field + raw_pb[old_field_end:]
        elif wt == 0:
            _, new_pos = pb_read_varint(raw_pb, new_pos)
        elif wt == 2:
            length, new_pos = pb_read_varint(raw_pb, new_pos)
            new_pos += length
        else:
            break
        pos = new_pos
    return raw_pb

def make_frame(msg_type, protobuf):
    total = 4 + len(protobuf)
    return struct.pack(">I", total) + struct.pack(">I", msg_type) + protobuf

# ═══════════════════════════════════════════════════════════════════════════
# SN 管理 — 从 /tmp/uu/.sn 统一读取
# ═══════════════════════════════════════════════════════════════════════════

TARGET_SN = None  # 运行时从 SN_FILE 加载

def load_sn():
    """从统一 SN 文件加载，失败返回 None"""
    global TARGET_SN
    if SN_FILE.exists():
        sn = SN_FILE.read_text().strip()
        if sn and len(sn) >= 12:
            return sn
    return None

def save_sn(sn):
    SN_FILE.write_text(sn)
    print(f'[SN] 写入统一 SN: {sn}', flush=True)

# ═══════════════════════════════════════════════════════════════════════════
# H3C 协议修改
# ═══════════════════════════════════════════════════════════════════════════

def fix_vendor_padding(raw_pb, field_num):
    """
    x86 binary 发 vendor 时带 null padding（如 b'h3c_\\x00\\x00\\x00\\x00' 7B），
    H3C NX30Pro 发的是纯 3B b'h3c'。修复 raw protobuf 字节。
    field_num: 2 = Register/FullRegister vendor, 4 = DeviceInfo vendor
    """
    tag_byte = (field_num << 3) | 2  # wire type 2
    prefix = bytes([tag_byte])
    # binary 发的是 7 字节带 padding: tag + len(7) + "h3c_...."
    needle_7 = prefix + b'\x07h3c_'
    idx = raw_pb.find(needle_7)
    if idx >= 0:
        before = raw_pb[:idx]
        after = raw_pb[idx + 9:]  # tag(1) + len(1) + data(7) = 9
        return before + pb_str(field_num, b'h3c') + after
    # 也试试 8 字节模式
    needle_8 = prefix + b'\x08h3c'
    idx = raw_pb.find(needle_8)
    if idx >= 0:
        before = raw_pb[:idx]
        after = raw_pb[idx + 10:]
        return before + pb_str(field_num, b'h3c') + after
    return raw_pb

def fix_sn_in_pb(raw_pb, sn_field, new_sn):
    """替换 protobuf 中的 SN 字段值为统一 SN"""
    old_sn_bytes = None
    # 用 pb_parse 找当前 SN
    parsed = pb_parse(raw_pb)
    current = str(parsed.get(sn_field, ''))
    if current and len(current) >= 12 and current != new_sn:
        old_sn_bytes = current.encode()
    if old_sn_bytes and old_sn_bytes in raw_pb:
        return raw_pb.replace(old_sn_bytes, new_sn.encode())
    return raw_pb

def enhance_register(raw_pb):
    """
    Register (0x24) → 注入 H3C NX30Pro 身份：
    1. 修复 f2 vendor padding (h3c_ → h3c)
    2. 替换 f6 version 为目标固件版本
    3. 确保 f4 product = NX30Pro
    4. 统一 SN
    """
    pb = fix_vendor_padding(raw_pb, 2)
    pb = pb_replace_field_str(pb, 6, TARGET_FW_VERSION)
    if TARGET_SN:
        pb = fix_sn_in_pb(pb, 3, TARGET_SN)

    parsed = pb_parse(pb)
    pb_out = bytearray(pb)
    if 4 not in parsed:
        pb_out += pb_str(4, 'NX30Pro')
    return bytes(pb_out)

def enhance_fullregister(raw_pb):
    """
    FullRegister (0x02) → 精简为 NX30Pro 格式（仅 f1+f2+f3）：
    x86 binary 发 11 字段 + JWT，真实 NX30Pro 只发 3 字段。
    """
    pb = fix_vendor_padding(raw_pb, 2)
    parsed = pb_parse(pb)
    sn_val = TARGET_SN if TARGET_SN else str(parsed.get(3, ''))
    clean = b''
    clean += pb_str(1, str(parsed.get(1, '')))  # f1: router_id
    clean += pb_str(2, 'h3c')                     # f2: vendor
    clean += pb_str(3, sn_val)                     # f3: SN
    return clean

def enhance_connectreply(raw_pb):
    """ConnectReply (0x11): 修复 f2 vendor + SN"""
    pb = fix_vendor_padding(raw_pb, 2)
    if TARGET_SN:
        pb = fix_sn_in_pb(pb, 3, TARGET_SN)
    return pb

def enhance_deviceinfo(raw_pb):
    """DeviceInfo (0x04): 修复 f4 vendor + f5 SN"""
    pb = fix_vendor_padding(raw_pb, 4)
    if TARGET_SN:
        pb = fix_sn_in_pb(pb, 5, TARGET_SN)
    return pb

def make_register_resp_not_bound():
    """
    构造 NX30Pro RegisterResp (0x25):
    code=0, msg="router not bound" → 触发 FullRegister 流程
    替代服务端返回的 "router not found"
    """
    pb = b''
    pb += pb_str(1, '0000000000000000')
    pb += pb_int(2, 0)
    pb += pb_str(3, 'router not bound')
    return make_frame(0x25, pb)

def suppress_fatal_log(protobuf):
    """检查是否包含需要拦截的 FATAL 日志"""
    parsed = pb_parse(protobuf)
    msg = str(parsed.get(2, ''))
    if 'unmatched sn' in msg or 'from_file' in msg:
        return True
    return False

def fix_arch_leak(raw_pb):
    """替换 x86_64 → aarch64（架构泄露）"""
    if b'x86_64' in raw_pb:
        return raw_pb.replace(b'x86_64', b'aarch64')
    return raw_pb

# ═══════════════════════════════════════════════════════════════════════════
# 消息类型名称（仅用于日志）
# ═══════════════════════════════════════════════════════════════════════════

TYPE_NAMES = {
    0x00: 'Heartbeat', 0x01: 'Pong', 0x02: 'FullRegister',
    0x03: 'FullRegisterResp', 0x04: 'DeviceInfo', 0x06: 'Device',
    0x0A: 'Log', 0x0E: 'ScanTarget', 0x10: 'ConnectReq',
    0x11: 'ConnectReply', 0x24: 'Register', 0x25: 'RegisterResp',
    0x26: 'CertResp', 0x30: 'ActivateResp', 0x3A: 'DirectAddr',
}

# ═══════════════════════════════════════════════════════════════════════════
# TLS MITM 核心
# ═══════════════════════════════════════════════════════════════════════════

def run_mitm():
    """主入口：启动 TLS MITM 服务"""
    if not CERT_FILE.exists() or not KEY_FILE.exists():
        print(f'[FATAL] TLS 证书缺失: {CERT_FILE} / {KEY_FILE}', flush=True)
        print(f'        请在 Dockerfile 中生成或挂载证书', flush=True)
        sys.exit(1)

    # 加载统一 SN
    global TARGET_SN
    TARGET_SN = load_sn()
    if TARGET_SN:
        print(f'[SN] 从 {SN_FILE} 加载: {TARGET_SN}', flush=True)
    else:
        print('[SN] 未找到 .sn 文件 — 将从首次 Register 消息捕获', flush=True)

    # TLS context (server side — 接受二进制连接)
    server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_ctx.load_cert_chain(str(CERT_FILE), str(KEY_FILE))
    server_ctx.verify_mode = ssl.CERT_NONE
    server_ctx.check_hostname = False
    server_ctx.minimum_version = ssl.TLSVersion.TLSv1
    server_ctx.set_ciphers('ALL:@SECLEVEL=0')

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((LISTEN_HOST, LISTEN_PORT))
    sock.listen(5)

    print(f'\n{"="*55}', flush=True)
    print(f'  UU MITM — H3C NX30Pro 身份注入', flush=True)
    print(f'  Listen:  {LISTEN_HOST}:{LISTEN_PORT}', flush=True)
    print(f'  → Real:  {REAL_HOST}:{REAL_PORT}', flush=True)
    print(f'  FW ver:  {TARGET_FW_VERSION}', flush=True)
    print(f'  SN:      {TARGET_SN or "(auto-capture)"}', flush=True)
    print(f'{"="*55}\n', flush=True)

    # 通知 start.sh MITM 已就绪
    print('[READY]', flush=True)

    conn_id = 0
    while True:
        try:
            client, addr = sock.accept()
            conn_id += 1
            t = threading.Thread(target=handle_connection, args=(client, addr, conn_id), daemon=True)
            t.start()
        except KeyboardInterrupt:
            print('\n[MITM] 关闭中...', flush=True)
            break

def handle_connection(client_sock, addr, conn_id):
    """处理一个二进制连接"""
    ts = datetime.now().strftime('%H:%M:%S')
    print(f'\n[{ts}] [+] 连接 #{conn_id} 来自 {addr[0]}:{addr[1]}', flush=True)

    # TLS — server side
    server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_ctx.load_cert_chain(str(CERT_FILE), str(KEY_FILE))
    server_ctx.verify_mode = ssl.CERT_NONE; server_ctx.check_hostname = False
    server_ctx.minimum_version = ssl.TLSVersion.TLSv1
    server_ctx.set_ciphers('ALL:@SECLEVEL=0')

    # TLS — client side (连真实服务器)
    client_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    client_ctx.check_hostname = False; client_ctx.verify_mode = ssl.CERT_NONE
    client_ctx.minimum_version = ssl.TLSVersion.TLSv1

    server_sock = None; cl_tls = None; srv_tls = None
    n_modified = 0; n_passed = 0
    global TARGET_SN

    try:
        client_sock.settimeout(10)
        cl_tls = server_ctx.wrap_socket(client_sock, server_side=True)
        print(f'  [TLS] 客户端: {cl_tls.version()} / {cl_tls.cipher()[0]}', flush=True)

        server_sock = socket.socket(); server_sock.settimeout(10)
        # SO_MARK=1 绕过 iptables DNAT，避免 MITM 自己流量被劫持循环
        server_sock.setsockopt(socket.SOL_SOCKET, 36, 1)
        server_sock.connect((REAL_HOST, REAL_PORT))
        srv_tls = client_ctx.wrap_socket(server_sock, server_hostname=REAL_HOST)
        print(f'  [TLS] 服务器: {srv_tls.version()} / {srv_tls.cipher()[0]}', flush=True)

        cl_tls.setblocking(False); srv_tls.setblocking(False)
        c_buf = b''; s_buf = b''

        while True:
            try:
                r, _, _ = select.select([cl_tls, srv_tls], [], [], 30.0)
            except:
                break
            if not r: continue

            for sock in r:
                is_client = (sock is cl_tls)
                src = cl_tls if is_client else srv_tls
                dst = srv_tls if is_client else cl_tls
                direction = 'C→S' if is_client else 'S→C'

                try:
                    data = src.recv(65536)
                except (ssl.SSLWantReadError, BlockingIOError):
                    continue
                except:
                    return

                if not data:
                    return

                # 累积到方向缓冲区
                if is_client:
                    c_buf += data; buf = c_buf
                else:
                    s_buf += data; buf = s_buf

                # 提取完整帧
                frames = []
                while len(buf) >= 4:
                    total_len = struct.unpack(">I", buf[:4])[0]
                    if total_len > 1024*1024: buf = b''; break
                    if len(buf) < 4 + total_len: break
                    raw = buf[:4+total_len]; buf = buf[4+total_len:]
                    msg_type = struct.unpack(">I", raw[4:8])[0]
                    pb = raw[8:]
                    frames.append((msg_type, pb, raw))

                if is_client:
                    c_buf = buf
                else:
                    s_buf = buf

                # 处理每帧
                for msg_type, protobuf, raw in frames:
                    tname = TYPE_NAMES.get(msg_type, f'0x{msg_type:02X}')
                    parsed = pb_parse(protobuf)
                    forward_data = raw  # 默认直接转发

                    # ──── 客户端 → 服务器 修改 ────
                    if is_client:
                        # ── Register (0x24): 注入 H3C NX30Pro 字段 ──
                        if msg_type == 0x24:
                            # 首次 Register 捕获 SN
                            sn = str(parsed.get(3, ''))
                            if sn and len(sn) >= 12 and TARGET_SN is None:
                                TARGET_SN = sn
                                save_sn(TARGET_SN)
                                print(f'[SN] 从 Register 捕获 SN: {TARGET_SN}', flush=True)

                            enhanced = enhance_register(protobuf)
                            if enhanced != protobuf:
                                forward_data = raw[:8] + enhanced
                                new_total = 4 + len(enhanced)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f'  [REG] Register H3C 注入: f2→h3c, f6→{TARGET_FW_VERSION}, '
                                      f'f4=NX30Pro, SN={TARGET_SN}', flush=True)
                                n_modified += 1

                        # ── FullRegister (0x02): 精简为 NX30Pro 3 字段 ──
                        elif msg_type == 0x02:
                            enhanced = enhance_fullregister(protobuf)
                            if enhanced != protobuf:
                                forward_data = raw[:8] + enhanced
                                new_total = 4 + len(enhanced)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f'  [FRG] FullRegister 精简: {len(pb_parse(protobuf))}→3 fields (NX30Pro)', flush=True)
                                n_modified += 1

                        # ── DeviceInfo (0x04): 修复 vendor + SN ──
                        elif msg_type == 0x04:
                            enhanced = enhance_deviceinfo(protobuf)
                            if enhanced != protobuf:
                                forward_data = raw[:8] + enhanced
                                new_total = 4 + len(enhanced)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f'  [DEV] DeviceInfo: f4→h3c, SN unified', flush=True)
                                n_modified += 1

                        # ── ConnectReply (0x11): 修复 vendor + SN ──
                        elif msg_type == 0x11:
                            enhanced = enhance_connectreply(protobuf)
                            if enhanced != protobuf:
                                forward_data = raw[:8] + enhanced
                                new_total = 4 + len(enhanced)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f'  [CRP] ConnectReply: f2→h3c, SN unified', flush=True)
                                n_modified += 1

                        # ── Log (0x0A): 拦截 FATAL + 修复架构泄露 ──
                        elif msg_type == 0x0A:
                            if suppress_fatal_log(protobuf):
                                print(f'  [LOG] SUPPRESSED FATAL: unmatched sn log', flush=True)
                                continue  # 不转发给服务器
                            modified = fix_arch_leak(protobuf)
                            if modified != protobuf:
                                forward_data = raw[:8] + modified
                                new_total = 4 + len(modified)
                                forward_data = struct.pack(">I", new_total) + forward_data[4:]
                                print(f'  [LOG] x86_64→aarch64', flush=True)

                        # ── 其他客户端消息: 直通（不修改加速隧道参数）──
                        else:
                            n_passed += 1

                    # ──── 服务器 → 客户端 修改 ────
                    else:
                        # ── RegisterResp (0x25): "router not found" → "router not bound" ──
                        if msg_type == 0x25:
                            msg = parsed.get(3, '')
                            if isinstance(msg, str) and 'not found' in msg.lower():
                                forward_data = make_register_resp_not_bound()
                                print(f'  [RRP] "router not found" → "router not bound" (触发 FullRegister)', flush=True)
                                n_modified += 1
                            elif isinstance(msg, str) and 'not bound' in msg.lower():
                                print(f'  [RRP] OK: router not bound — 等待 FullRegister', flush=True)
                                n_passed += 1
                            else:
                                n_passed += 1
                        else:
                            n_passed += 1

                    # 转发（可能已修改）
                    try:
                        dst.sendall(forward_data)
                    except:
                        return

    except Exception as e:
        print(f'  [!] 错误: {e}', flush=True)
        import traceback; traceback.print_exc()
    finally:
        for s in [cl_tls, srv_tls, client_sock, server_sock]:
            try: s.close()
            except: pass
        print(f'  [*] 连接 #{conn_id} 关闭 (修改: {n_modified}, 直通: {n_passed})', flush=True)

# ═══════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    run_mitm()
