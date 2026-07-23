$file = "d:\Desktop\aiiii\hafiz\website\og-image.jpg"
$bytes = [System.IO.File]::ReadAllBytes($file)
Write-Host "File size: $($bytes.Length) bytes"
$hex = [BitConverter]::ToString($bytes[0..15])
Write-Host "First 16 bytes: $hex"

# Check if it's a valid JPEG (starts with FF D8 FF)
if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8 -and $bytes[2] -eq 0xFF) {
    Write-Host "Valid JPEG header"
} else {
    Write-Host "NOT a valid JPEG header!"
}

# Check PNG header
$pngFile = "d:\Desktop\aiiii\hafiz\website\og-image.png"
$pngBytes = [System.IO.File]::ReadAllBytes($pngFile)
Write-Host "`nPNG file size: $($pngBytes.Length) bytes"
$pngHex = [BitConverter]::ToString($pngBytes[0..15])
Write-Host "PNG first 16 bytes: $pngHex"
if ($pngBytes[0] -eq 0x89 -and $pngBytes[1] -eq 0x50 -and $pngBytes[2] -eq 0x4E -and $pngBytes[3] -eq 0x47) {
    Write-Host "Valid PNG header"
} else {
    Write-Host "NOT a valid PNG header!"
}
