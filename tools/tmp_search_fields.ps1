$nx30 = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$b = [System.IO.File]::ReadAllBytes($nx30)

# Search for known factoryinfo keys
$keys = @('productname', 'ethaddr', 'hardversion', 'bootversion', 'manucode',
          'factoryinfo', 'h3c_info', 'UU_SN', 'UU_MODEL', 'UU_VENDOR',
          'register', 'model', 'vendor', 'device', 'from_file',
          'request', 'reply', 'resp', 'msg_type', 'serial',
          'NX30Pro', 'h3c-nx30pro', 'openwrt')

foreach ($key in $keys) {
    $kb = [System.Text.Encoding]::ASCII.GetBytes($key)
    $kl = $kb.Length
    $found = $false
    
    # Search for exact match
    for ($i = 0; $i -le $b.Length - $kl; $i++) {
        $match = $true
        for ($j = 0; $j -lt $kl; $j++) {
            if ($b[$i + $j] -ne $kb[$j]) { $match = $false; break }
        }
        if ($match) {
            Write-Output ("PLAINTEXT '{0}' at file offset 0x{1:X} ({1})" -f $key, $i)
            $found = $true
            break
        }
    }
    
    if (-not $found) {
        # Search for XOR-encoded with single-byte key
        for ($k = 1; $k -le 255; $k++) {
            for ($i = 0; $i -le $b.Length - $kl; $i++) {
                $match = $true
                for ($j = 0; $j -lt $kl; $j++) {
                    if (($b[$i + $j] -bxor $k) -ne $kb[$j]) { $match = $false; break }
                }
                if ($match) {
                    Write-Output ("XOR(key=0x{0:X2}) '{1}' at file offset 0x{2:X} ({2})" -f $k, $key, $i)
                    $found = $true
                    break
                }
            }
            if ($found) { break }
        }
    }
    
    if (-not $found) {
        Write-Output ("NOT FOUND (plain or single-byte XOR): '{0}'" -f $key)
    }
}
