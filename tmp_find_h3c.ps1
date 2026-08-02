# Find "h3c" strings in NX30Pro binary with surrounding context
$nx30 = [System.IO.File]::ReadAllBytes('d:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin')
$x86 = [System.IO.File]::ReadAllBytes('d:\code03\uugamebooster-docker\bin\uuplugin')

function Find-Context($data, $pattern, $label) {
    $idx = 0
    $found = $false
    while (($idx = [Array]::IndexOf($data, [byte][char]$pattern[0], $idx)) -ge 0) {
        # Check if full pattern matches
        $match = $true
        for ($j = 0; $j -lt $pattern.Length; $j++) {
            if ($data[$idx + $j] -ne [byte][char]$pattern[$j]) {
                $match = $false
                break
            }
        }
        if ($match) {
            $found = $true
            $start = [Math]::Max(0, $idx - 30)
            $end = [Math]::Min($data.Length, $idx + $pattern.Length + 30)
            $hex = ($data[$start..($end-1)] | ForEach-Object { $_.ToString('X2') }) -join ' '
            $raw = -join ($data[$start..($end-1)] | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } })
            Write-Output ("  $label offset 0x" + $idx.ToString('X8') + ":")
            Write-Output ("    hex: " + $hex)
            Write-Output ("    raw: " + $raw)
        }
        $idx++
    }
    if (-not $found) {
        Write-Output ("  ${label}: NOT FOUND in plaintext")
    }
}

Write-Output "=== Searching NX30Pro aarch64 ==="
Find-Context $nx30 "h3c" "h3c"
Find-Context $nx30 "h3c_" "h3c_"

Write-Output "`n=== Searching x86_64 ==="
Find-Context $x86 "h3c" "h3c"
Find-Context $x86 "h3c_" "h3c_"
Find-Context $x86 "openwrt" "openwrt"

# Also check: does NX30Pro have "openwrt"?
Write-Output "`n=== NX30Pro: openwrt ==="
Find-Context $nx30 "openwrt" "openwrt"

# Check for UU_SN, UU_MODEL in NX30Pro
Write-Output "`n=== NX30Pro: UU_ strings ==="
Find-Context $nx30 "UU_SN" "UU_SN"
Find-Context $nx30 "UU_MODEL" "UU_MODEL"
Find-Context $nx30 "UU_VENDOR" "UU_VENDOR"
