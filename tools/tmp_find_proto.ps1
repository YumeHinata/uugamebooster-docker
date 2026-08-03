$f = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$t = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($f))

Write-Output "=== uu_router_messages message types ==="
$pat = [regex]::Matches($t, 'N\d+uu_router_messages\d+(\w+)E')
$seen = @{}
foreach ($m in $pat) {
    $name = $m.Groups[1].Value
    if (-not $seen[$name]) {
        $ctx = $t.Substring([Math]::Max(0,$m.Index-10), [Math]::Min(60,$t.Length-$m.Index+10)) -replace '[^\x20-\x7E]','.'
        Write-Output ("  uu_router_messages::{0} at 0x{1:X}" -f $name, $m.Index)
        $seen[$name] = $true
    }
}

Write-Output "`n=== uuctl message types ==="
$pat = [regex]::Matches($t, 'N\d+uuctl\d+(\w+)E')
$seen = @{}
foreach ($m in $pat) {
    $name = $m.Groups[1].Value
    if (-not $seen[$name]) {
        Write-Output ("  uuctl::{0} at 0x{1:X}" -f $name, $m.Index)
        $seen[$name] = $true
    }
}

Write-Output "`n=== All message-like names (C++ mangled) ==="
$pat = [regex]::Matches($t, 'N\d+(\w+?)\d+(Register|Request|Response|Reply|Message|Info|Config|Report|Heartbeat|Login|Auth|Connect)[a-zA-Z]*E')
$seen = @{}
foreach ($m in $pat) {
    $ns = $m.Groups[1].Value
    $name = $m.Groups[2].Value
    $full = "{0}::{1}" -f $ns, $name
    if (-not $seen[$full]) {
        Write-Output ("  {0} at 0x{1:X}" -f $full, $m.Index)
        $seen[$full] = $true
    }
}

Write-Output "`n=== Also check x86 binary for same messages ==="
$x86f = 'd:\code03\uugamebooster-docker\rootfs\x86.uu\uuplugin'
if (Test-Path $x86f) {
    $x86t = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($x86f))
    $pat = [regex]::Matches($x86t, 'N\d+uu_router_messages\d+(\w+)E')
    $seen = @{}
    foreach ($m in $pat) {
        $name = $m.Groups[1].Value
        if (-not $seen[$name]) {
            Write-Output ("  x86: uu_router_messages::{0} at 0x{1:X}" -f $name, $m.Index)
            $seen[$name] = $true
        }
    }
}
