$lines = Get-Content "d:\code03\uugamebooster-docker\mitm_debug2.log"
Write-Output "Total lines: $($lines.Count)"

foreach ($line in $lines) {
    if ($line -match "Connection|closed|peer.close|FullRegisterResp|BoundUser|Device.msg|DirectAddr|segfault|restart|attempt|killed|signal.15") {
        $out = $line
        if ($out.Length -gt 500) { $out = $out.Substring(0,500) + "..." }
        Write-Output $out
    }
}
