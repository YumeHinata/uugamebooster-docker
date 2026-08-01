#!/usr/bin/env python3
"""Probe server with different registration formats to find the correct one."""
import socket, ssl, sys, time
sys.path.insert(0, 'tools' if 'tools' not in sys.path[0] else '')
from uu_analyzer import pb_encode_dict, make_frame, read_frame

HOST = '106.2.95.34'
PORT = 16000

def test_registration(desc, pb_dict, msg_type=0x24):
    sock = socket.socket(); sock.settimeout(10)
    sock.connect((HOST, PORT))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    tls = ctx.wrap_socket(sock, server_hostname='rglg.uu.163.com')
    
    # Send heartbeat first
    hb = pb_encode_dict({1:'ping', 2:'hello'})
    tls.sendall(make_frame(0x00, hb))
    time.sleep(0.3)
    try:
        read_frame(tls)
    except:
        pass
    
    # Send the test message
    pb = pb_encode_dict(pb_dict)
    frame = make_frame(msg_type, pb)
    tls.sendall(frame)
    print(f'\n[{desc}]')
    print(f'  Sent: type=0x{msg_type:02x}, pb_size={len(pb)}')
    for k, v in pb_dict.items():
        if isinstance(v, dict):
            print(f'    field {k}: {v}')
        else:
            print(f'    field {k}: \"{v}\"')
    
    tls.settimeout(5)
    try:
        r = read_frame(tls)
        if r:
            parsed = r.parse()
            print(f'  >>> Response: type=0x{r.msg_type:02x} ({r.type_name})')
            for k, v in parsed.items():
                if isinstance(v, str):
                    print(f'    field {k}: \"{v}\"')
                else:
                    print(f'    field {k}: {v}')
        else:
            print(f'  >>> No response')
    except Exception as e:
        print(f'  >>> Timeout: {e}')
    tls.close()
    time.sleep(1)

# Test many registration formats
tests = [
    # Original format from MITM capture
    ('Original (from MITM)', 0x24, {
        1: '0000000000000000',
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
    }),
    # With from_file flag (field 6 = 1 means SN from file)
    ('With from_file=1', 0x24, {
        1: '0000000000000000',
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
        6: 1,
    }),
    # from_file=0
    ('With from_file=0', 0x24, {
        1: '0000000000000000',
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
        6: 0,
    }),
    # Try ConnectRequest (type 0x10)
    ('ConnectRequest', 0x10, {
        1: '12345678900987654321',
        2: 'h3cnx30',
        3: 'NX30Pro',
    }),
    # Device message (type 0x06)
    ('Device', 0x06, {
        1: '12345678900987654321',
        2: 'NX30Pro',
        3: 'h3cnx30',
        4: 'v14.3.0',
    }),
    # FullRegister (type 0x02)
    ('FullRegister', 0x02, {
        1: '0000000000000000',
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
        6: 1,  # OS type?
        7: 'aarch64',
    }),
    # Minimal
    ('Minimal', 0x24, {
        2: 'h3cnx30',
        3: '12345678900987654321',
    }),
    # With ethaddr
    ('With MAC', 0x24, {
        1: '0000000000000000',
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
        6: 1,
        7: 'xx:xx:xx:xx:xx:xx',
    }),
    # Different model formats
    ('model=h3c_nx30pro', 0x24, {
        1: '0000000000000000',
        2: 'h3c_nx30pro',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
    }),
    ('model=NX30Pro', 0x24, {
        1: '0000000000000000',
        2: 'NX30Pro',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
    }),
    # Different product names
    ('product=H3C', 0x24, {
        1: '0000000000000000',
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'H3C',
        5: 'v14.3.0',
    }),
    # Extra fields
    ('Extra fields', 0x24, {
        1: '0000000000000000',
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'NX30Pro',
        5: 'v14.3.0',
        6: 0,
        7: 'h3cnx30-aarch64',
        8: 'Linux',
        9: 'VER.A',
        10: '100',
    }),
    # Try with manucode field name
    ('field3=manucode', 0x24, {
        2: 'h3cnx30',
        3: '12345678900987654321',
        4: 'NX30Pro',
    }),
]

for desc, mtype, fields in tests:
    test_registration(desc, fields, mtype)
