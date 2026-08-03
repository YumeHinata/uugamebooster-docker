$nx30 = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$b = [System.IO.File]::ReadAllBytes($nx30)
$t = [System.Text.Encoding]::ASCII.GetString($b)

# Find all ASCII word sequences 3-30 chars
$matches = [regex]::Matches($t, '[A-Za-z_][A-Za-z_0-9]{2,30}')
$freq = @{}
foreach ($m in $matches) {
    $w = $m.Value.ToLower()
    if ($freq[$w]) { $freq[$w]++ } else { $freq[$w] = 1 }
}

Write-Output "=== All strings with frequency >= 3 ==="
$freq.GetEnumerator() | Where-Object { $_.Value -ge 3 } | Sort-Object Value -Descending | ForEach-Object {
    Write-Output ('{0} ({1})' -f $_.Key, $_.Value)
}

Write-Output "`n=== Search for proto/message/field related strings ==="
$protoPat = [regex]::Matches($t, '.{0,20}(register|request|req|resp|response|device|product|serial|model|vendor|field|proto|message).{0,20}')
foreach ($m in $protoPat) {
    $ctx = $m.Value -replace '[^\x20-\x7E]', '.'
    Write-Output ('  pos={0}: {1}' -f $m.Index, $ctx)
}
