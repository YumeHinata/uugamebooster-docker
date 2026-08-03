$lines = Get-Content "d:\code03\uugamebooster-docker\mitm_debug.log"
$last = $lines[94]
if ($last.Length -gt 1500) { $last = $last.Substring(0,1500) + "..." }
Write-Output "Line 95 (last): $last"
Write-Output ""
Write-Output "Total lines: $($lines.Count)"
