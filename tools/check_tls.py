#!/usr/bin/env python3
"""Check TLS server certificate details and whether mTLS is required."""
import socket, ssl, json

sock = socket.socket(); sock.settimeout(10)
sock.connect(('106.2.95.34', 16000))

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

tls = ctx.wrap_socket(sock, server_hostname='rglg.uu.163.com')
print(f"TLS version: {tls.version()}")
print(f"Cipher: {tls.cipher()}")

# Get server cert as DER
cert_der = tls.getpeercert(binary_form=True)
print(f"Server cert DER: {len(cert_der)} bytes")

# Parse with cryptography
from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.x509.oid import NameOID, ExtensionOID

c = x509.load_der_x509_certificate(cert_der, default_backend())

print(f"\nSubject CN: {c.subject.get_attributes_for_oid(NameOID.COMMON_NAME)}")
print(f"Issuer CN: {c.issuer.get_attributes_for_oid(NameOID.COMMON_NAME)}")
print(f"Serial: {c.serial_number}")
print(f"Not valid before: {c.not_valid_before_utc}")
print(f"Not valid after: {c.not_valid_after_utc}")

# Check SAN
try:
    san = c.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
    print(f"SAN: {san.value}")
except:
    print("No SAN extension")

# Check all extensions
print(f"\nExtensions ({len(c.extensions)}):")
for ext in c.extensions:
    print(f"  {ext.oid._name}: critical={ext.critical}")

# Check if cert is ECDSA or RSA
from cryptography.hazmat.primitives.asymmetric import ec, rsa
pubkey = c.public_key()
if isinstance(pubkey, ec.EllipticCurvePublicKey):
    print(f"\nPublic key: EC {pubkey.curve.name} ({pubkey.key_size} bits)")
elif isinstance(pubkey, rsa.RSAPublicKey):
    print(f"\nPublic key: RSA {pubkey.key_size} bits")
else:
    print(f"\nPublic key: {type(pubkey).__name__}")

tls.close()
print("\nDone.")
