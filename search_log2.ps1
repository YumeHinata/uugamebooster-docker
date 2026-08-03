$lines = Get-Content "d:\code03\uugamebooster-docker\mitm_debug.log"
foreach ($line in $lines) {
    if ($line -match 'closed|peer close|Error|FullRegister|FullRegisterResp|Connection \#|SUPPRESSED|FATAL|bound|success|0x03|Heartbeat') {
        $out = $line
        if ($out.Length -gt 1000) { $out = $out.Substring(0,1000) + "..." }
        Write-Output $out
    }
}
