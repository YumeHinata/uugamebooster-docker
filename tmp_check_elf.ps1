# Check NX30Pro uuplugin ELF details
$nx30 = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$bytes = [System.IO.File]::ReadAllBytes($nx30)

# ELF header
$ident = [char]$bytes[0] + [char]$bytes[1] + [char]$bytes[2] + [char]$bytes[3]
$class = if ($bytes[4] -eq 1) { "32-bit" } elseif ($bytes[4] -eq 2) { "64-bit" } else { "?" }
$endian = if ($bytes[5] -eq 1) { "LE" } elseif ($bytes[5] -eq 2) { "BE" } else { "?" }
$machine = $bytes[18] + ($bytes[19] * 256)
$arch = switch ($machine) {
    0x003E { "x86_64" }
    0x00B7 { "aarch64" }
    0x0028 { "ARM" }
    default { "0x" + $machine.ToString('X4') }
}
$type = $bytes[16] + ($bytes[17] * 256)
$typeName = switch ($type) {
    2 { "EXEC" }
    3 { "DYN (PIE/shared)" }
    default { $type.ToString() }
}

Write-Output ("NX30Pro uuplugin: " + $class + " " + $arch + " " + $endian + " type=" + $typeName)
Write-Output ("Size: " + $bytes.Length + " bytes")

# Check for dynamic sections
# Find .dynamic, .dynsym, .interp
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
if ($text -match '\.interp') { Write-Output "Has .interp (dynamic linker)" }
if ($text -match '\.dynamic') { Write-Output "Has .dynamic section" }
if ($text -match '\.dynsym') { Write-Output "Has .dynsym (dynamic symbols)" }

# Find NEEDED libraries
$needed = [regex]::Matches($text, 'NEEDED\x00([^\x00]+)')
if ($needed.Count -gt 0) {
    Write-Output ("`nShared libraries needed:")
    foreach ($m in $needed) {
        Write-Output ("  " + $m.Groups[1].Value)
    }
} else {
    Write-Output "No NEEDED entries found (possibly statically linked)"
}
