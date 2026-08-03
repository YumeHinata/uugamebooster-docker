$content = Get-Content "c:\Users\YumeH\AppData\Local\Temp\aicoding-text-field\659d8fa5-e95f-420b-8f9c-cb756e2eec04\text-field-content-de03a250-c391-48ea-8387-4784c99c3630.txt" -Raw

# Split by newlines
$lines = $content -split "`n"

# Find key patterns
$patterns = @("SIGSEGV", "SIGABRT", "open.*openssl", "tun", "TUNSET", "SIOC", "exit_group", "write.*Broken", "SIGPIPE", "flock.*EAGAIN", "segfault", "+++ killed", "connect\(")
$seen = @{}

foreach ($line in $lines) {
    foreach ($pat in $patterns) {
        if ($line -match $pat -and -not $seen.ContainsKey($line.Substring(0, [Math]::Min(80, $line.Length)))) {
            $key = $line.Substring(0, [Math]::Min(80, $line.Length))
            $seen[$key] = $true
            $out = $line.Trim()
            if ($out.Length -gt 500) { $out = $out.Substring(0,500) + "..." }
            Write-Output $out
            break
        }
    }
}
