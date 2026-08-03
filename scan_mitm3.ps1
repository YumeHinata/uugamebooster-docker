$lines = Get-Content "d:\code03\uugamebooster-docker\mitm_debug2.log"

# Show all lines with message type (CLIENT->SERVER or SERVER->CLIENT)
# and all connection open/close events
for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    # Show connection events and message directions
    if ($l -match "Connection #[0-9]|CLIENT.*SERVER|SERVER.*CLIENT|Heartbeat|DirectAddr|FullRegister|Device |BoundUser|FATAL|FORCE|tunnel|SUPPRESSED" -and $l -notmatch "SUPPRESSED") {
        $out = $l
        if ($out.Length -gt 600) { $out = $out.Substring(0,600) + "..." }
        Write-Output "[$i] $out"
    }
}
