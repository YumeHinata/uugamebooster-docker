$lines = Get-Content "d:\code03\uugamebooster-docker\mitm_debug.log"
foreach ($line in $lines) {
    if ($line -match 'closed|peer close|not found|Activate|unbound|failed|ConnectReq|ConnectReply') {
        $out = $line
        if ($out.Length -gt 800) { $out = $out.Substring(0,800) + "..." }
        Write-Output $out
    }
}
