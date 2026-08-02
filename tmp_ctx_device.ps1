$nx30 = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$b = [System.IO.File]::ReadAllBytes($nx30)

# DeviceCommonInfo at 0x2698A0, uu_router_messages list starts at ~0x26F6E0
# Let me dump both regions

function DumpContext($pos, $label, $len=400) {
    $start = [Math]::Max(0, $pos - 100)
    $end = [Math]::Min($b.Length, $pos + $len)
    Write-Output "=== Context around $label (0x$($pos.ToString('X')) - 0x$($end.ToString('X'))) ==="
    for ($i = $start; $i -lt $end; $i += 16) {
        $hex = ''
        $ascii = ''
        for ($j = 0; $j -lt 16; $j++) {
            if ($i + $j -ge $end) { break }
            $bt = $b[$i + $j]
            $hex += '{0:X2} ' -f $bt
            if ($bt -ge 32 -and $bt -le 126) { $ascii += [char]$bt } else { $ascii += '.' }
        }
        Write-Output ('0x{0:X6}: {1} {2}' -f $i, $hex.PadRight(48), $ascii)
    }
}

DumpContext 0x2698A0 "DeviceCommonInfo"
Write-Output "`n"
DumpContext 0x26F6E0 "uu_router_messages types"
Write-Output "`n"
DumpContext 0x262CD8 "model+serial region (h3c_, h3c-nx30pro)"
