# Check what's in rootfs/lib and their architecture
$rootfs = 'd:\code03\uugamebooster-docker\rootfs'
Write-Output "=== rootfs/lib/ files ==="
Get-ChildItem "$rootfs\lib\" | ForEach-Object { Write-Output ("  " + $_.Name + " (" + $_.Length + " bytes)") }

Write-Output "`n=== rootfs/x86.uu/ files ==="
Get-ChildItem "$rootfs\x86.uu\" 2>$null | ForEach-Object { Write-Output ("  " + $_.Name + " (" + $_.Length + " bytes)") }

# Check ELF magic of key files
Write-Output "`n=== ELF header check ==="
$files = @(
    "$rootfs\lib\libc.so",
    "$rootfs\x86.uu\uuplugin",
    "$rootfs\uuplugin",
    "$rootfs\xuplugin-guardian"
)
foreach ($f in $files) {
    if (Test-Path $f) {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $magic = [char]$bytes[0] + [char]$bytes[1] + [char]$bytes[2] + [char]$bytes[3]
        $class = if ($bytes[4] -eq 1) { "32-bit" } elseif ($bytes[4] -eq 2) { "64-bit" } else { "?" }
        $endian = if ($bytes[5] -eq 1) { "LE" } elseif ($bytes[5] -eq 2) { "BE" } else { "?" }
        $machine = $bytes[18] * 256 + $bytes[19]
        $arch = switch ($machine) {
            0x003E { "x86_64" }
            0x00B7 { "aarch64" }
            0x0028 { "ARM" }
            default { "0x" + $machine.ToString('X4') }
        }
        Write-Output ("  " + (Split-Path $f -Leaf) + ": ELF " + $class + " " + $endian + " " + $arch)
    }
}

# Check NX30Pro binary
$nx30 = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
if (Test-Path $nx30) {
    $bytes = [System.IO.File]::ReadAllBytes($nx30)
    $class = if ($bytes[4] -eq 1) { "32-bit" } elseif ($bytes[4] -eq 2) { "64-bit" } else { "?" }
    $machine = $bytes[18] * 256 + $bytes[19]
    $arch = switch ($machine) {
        0x003E { "x86_64" }
        0x00B7 { "aarch64" }
        0x0028 { "ARM" }
        default { "0x" + $machine.ToString('X4') }
    }
    Write-Output ("`nNX30Pro uuplugin: ELF " + $class + " " + $arch + " (" + (Get-Item $nx30).Length + " bytes)")
}
