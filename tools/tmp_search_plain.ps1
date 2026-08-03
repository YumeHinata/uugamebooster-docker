$f = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$t = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($f))

$terms = @('ethaddr','hardversion','bootversion','factoryinfo','h3c_info',
           'Register','register','from_file','from file','unmatched',
           'router','Router','device','Device','serial','Serial',
           'model','Model','vendor','Vendor','manucode','productname',
           'SN','NAT','nat_type','wan_if','lan_if',
           '0x24','0x25','0x02','protobuf','message',
           'field','Field','hw_nat','hwver','bootver',
           'mac_addr','MAC','eth0','br-lan')

foreach ($t2 in $terms) {
    $idx = 0
    $count = 0
    while (($idx = $t.IndexOf($t2, $idx, [StringComparison]::Ordinal)) -ge 0) {
        if ($count -eq 0) {
            $ctxStart = [Math]::Max(0, $idx - 40)
            $ctxEnd = [Math]::Min($t.Length, $idx + $t2.Length + 40)
            $ctx = $t.Substring($ctxStart, $ctxEnd - $ctxStart) -replace '[^\x20-\x7E]','.'
            Write-Output ("'{0}' at 0x{1:X}: ...{2}..." -f $t2, $idx, $ctx)
        }
        $count++
        $idx++
    }
    if ($count -gt 1) {
        Write-Output ("  ({0} total occurrences)" -f $count)
    }
}
