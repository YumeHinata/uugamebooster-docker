"""SSH to router and clean Docker + container log resources."""
import paramiko

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('192.168.0.1', username='root', password='HADESsamlechen12', timeout=10)

def run(cmd):
    stdin, stdout, stderr = c.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='replace').strip()
    err = stderr.read().decode('utf-8', errors='replace').strip()
    if err:
        print(f"  [stderr] {err}")
    return out

print("=== BEFORE ===")
print(run("df -h /"))

# 1. Truncate big logs inside container
print("\n=== TRUNCATE CONTAINER /tmp LOGS ===")
print(run("docker exec UUgamebooster sh -c '> /tmp/mitm_frames.log && > /tmp/iptables_wrap.log && > /tmp/nft_wrap.log && > /tmp/natflushd.log && > /tmp/uuplugin_stderr.log && > /tmp/conntrack_wrapper.log 2>/dev/null && echo OK'"))

# 2. Truncate old strace logs (if any)
print(run("docker exec UUgamebooster sh -c 'rm -f /tmp/strace_uuplugin.log /tmp/uuplugin_strace.log /tmp/qemu.log /tmp/g_full.log 2>/dev/null && echo strace-logs-cleaned'"))

# 3. Truncate Docker json-log (host side)
print("\n=== TRUNCATE DOCKER JSON-LOG ===")
print(run("truncate -s 0 /var/lib/docker/containers/*/*json.log 2>/dev/null && echo OK || echo 'no truncate, trying sh'"))
print(run("find /var/lib/docker/containers -name '*json.log' -exec sh -c '> {}' \\; 2>/dev/null && echo json-logs-truncated"))

# 4. Docker prune (dangling images, build cache)
print("\n=== DOCKER PRUNE ===")
print(run("docker system prune -f 2>&1"))

# 5. Remove old unused images if any
print("\n=== REMOVE DANGLING IMAGES ===")
print(run("docker image prune -f 2>&1"))

print("\n=== AFTER ===")
print(run("df -h /"))
print(run("docker system df"))

# Verify container logs are clean
print("\n=== CONTAINER /tmp AFTER ===")
print(run("docker exec UUgamebooster du -sh /tmp/*.log 2>/dev/null || echo 'no logs'"))

c.close()
