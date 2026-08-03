$lines = Get-Content "d:\code03\uugamebooster-docker\mitm_debug.log"
for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -match '12:09:3[0-9]|12:09:4[0-9]|12:09:5|12:10:|DirectAddr|0x3a|0x06|Device[^I]|closed') {
        $out = $l
        if ($out.Length -gt 1800) { $out = $out.Substring(0,1800) + "..." }
        Write-Output "[$i] $out"
    }
}
