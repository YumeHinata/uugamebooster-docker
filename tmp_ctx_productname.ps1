$nx30 = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$b = [System.IO.File]::ReadAllBytes($nx30)

# productname found at 0x2687C0 - dump surrounding context
$pos = 0x2687C0
$start = [Math]::Max(0, $pos - 200)
$end = [Math]::Min($b.Length, $pos + 300)

Write-Output "=== Context around productname (0x2687C0) ==="
for ($i = $start; $i -lt $end; $i += 16) {
    $hex = ''
    $ascii = ''
    for ($j = 0; $j -lt 16; $j++) {
        if ($i + $j -ge $end) { break }
        $bt = $b[$i + $j]
        $hex += '{0:X2} ' -f $bt
        if ($bt -ge 32 -and $bt -le 126) {
            $ascii += [char]$bt
        } else {
            $ascii += '.'
        }
    }
    $marker = ''
    if ($i -le $pos -and $i + 16 -gt $pos) { $marker = ' <-- productname' }
    Write-Output ('0x{0:X6}: {1} {2}{3}' -f $i, $hex.PadRight(48), $ascii, $marker)
}

# Also look for other strings near this area
Write-Output "`n=== All printable strings near 0x2687C0 ==="
for ($i = [Math]::Max(0, $pos - 500); $i -lt [Math]::Min($b.Length, $pos + 500); $i++) {
    if ($b[$i] -ge 32 -and $b[$i] -le 126) {
        $s = ''
        $j = $i
        while ($j -lt $b.Length -and $b[$j] -ge 32 -and $b[$j] -le 126 -and ($j - $i) -lt 50) {
            $s += [char]$b[$j]
            $j++
        }
        if ($s.Length -ge 4) {
            Write-Output ('  0x{0:X}: "{1}"' -f $i, $s)
            $i = $j
        }
    }
}
