$nx30 = 'd:\code03\uugamebooster-docker\bin\NX30Pro_v14.4.20\uuplugin'
$bytes = [System.IO.File]::ReadAllBytes($nx30)

# Parse ELF64 program headers to find PT_INTERP
# ELF64 header: e_phoff at offset 32 (8 bytes), e_phentsize at 54 (2), e_phnum at 56 (2)
$phoff = [BitConverter]::ToInt64($bytes, 32)
$phentsize = [BitConverter]::ToInt16($bytes, 54)
$phnum = [BitConverter]::ToInt16($bytes, 56)

Write-Output ("phoff=" + $phoff + " phentsize=" + $phentsize + " phnum=" + $phnum)

for ($i = 0; $i -lt $phnum; $i++) {
    $off = $phoff + ($i * $phentsize)
    $p_type = [BitConverter]::ToInt32($bytes, $off)
    if ($p_type -eq 3) { # PT_INTERP
        $p_offset = [BitConverter]::ToInt64($bytes, $off + 8)
        $p_filesz = [BitConverter]::ToInt64($bytes, $off + 32)
        $interp = [System.Text.Encoding]::ASCII.GetString($bytes, $p_offset, $p_filesz - 1)
        Write-Output ("PT_INTERP: " + $interp)
    }
}

# Also find DT_NEEDED entries in .dynamic section
# Search for .dynamic section header
# Section header table: e_shoff at offset 40 (8 bytes)
$shoff = [BitConverter]::ToInt64($bytes, 40)
$shentsize = [BitConverter]::ToInt16($bytes, 58)
$shnum = [BitConverter]::ToInt16($bytes, 60)
$shstrndx = [BitConverter]::ToInt16($bytes, 62)

Write-Output ("`nshoff=" + $shoff + " shentsize=" + $shentsize + " shnum=" + $shnum)

# Read section header string table
$shstrOff = $shoff + ($shstrndx * $shentsize)
$shstr_offset = [BitConverter]::ToInt64($bytes, $shstrOff + 24)
$shstr_size = [BitConverter]::ToInt64($bytes, $shstrOff + 32)

for ($i = 0; $i -lt $shnum; $i++) {
    $off = $shoff + ($i * $shentsize)
    $sh_name_idx = [BitConverter]::ToInt32($bytes, $off)
    $sh_type = [BitConverter]::ToInt32($bytes, $off + 4)
    $sh_addr = [BitConverter]::ToInt64($bytes, $off + 16)
    $sh_offset = [BitConverter]::ToInt64($bytes, $off + 24)
    $sh_size = [BitConverter]::ToInt64($bytes, $off + 32)
    
    # Get section name
    $nameEnd = [Array]::IndexOf($bytes, 0, $shstr_offset + $sh_name_idx)
    if ($nameEnd -lt 0) { $nameEnd = $shstr_offset + $sh_name_idx + 20 }
    $name = [System.Text.Encoding]::ASCII.GetString($bytes, $shstr_offset + $sh_name_idx, $nameEnd - $shstr_offset - $sh_name_idx)
    
    if ($name -eq '.dynamic') {
        Write-Output ("`n.dynamic at file offset " + $sh_offset + " size " + $sh_size)
        
        # Parse DT_NEEDED entries
        for ($d = 0; $d -lt $sh_size; $d += 16) {
            $d_tag = [BitConverter]::ToInt64($bytes, $sh_offset + $d)
            $d_val = [BitConverter]::ToInt64($bytes, $sh_offset + $d + 8)
            if ($d_tag -eq 1) { # DT_NEEDED
                # Need to read from .dynstr
                Write-Output ("  DT_NEEDED offset in .dynstr: " + $d_val)
            }
            if ($d_tag -eq 0) { break } # DT_NULL
        }
    }
    
    if ($name -eq '.dynstr') {
        Write-Output ("`.dynstr at file offset " + $sh_offset + " size " + $sh_size)
        $dynstr_off = $sh_offset
    }
}
