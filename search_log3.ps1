$lines = Get-Content "d:\code03\uugamebooster-docker\mitm_debug.log"
$count = $lines.Count
$start = [Math]::Max(0, $count - 8)
for ($i = $start; $i -lt $count; $i++) {
    $l = $lines[$i]
    if ($l.Length -gt 2000) { $l = $l.Substring(0,2000) + "..." }
    Write-Output "[$i] $l"
}
