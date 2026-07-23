try {
    $response = Invoke-WebRequest -Uri 'https://hafizapp.xyz/og-image.jpg' -UseBasicParsing -MaximumRedirection 5
    Write-Host "Status: $($response.StatusCode)"
    Write-Host "Content-Type: $($response.Headers['Content-Type'])"
    Write-Host "Content-Length: $($response.Headers['Content-Length'])"
    Write-Host "Response body size: $($response.Content.Length) bytes"
    
    # Check if Content is bytes or string
    if ($response.Content -is [byte[]]) {
        $b = $response.Content[0..7]
        Write-Host "First 8 bytes (hex):" ([BitConverter]::ToString($b))
    } else {
        Write-Host "Content type: $($response.Content.GetType().Name)"
        Write-Host "First 100 chars:" $response.Content.Substring(0, [Math]::Min(100, $response.Content.Length))
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Inner: $($_.Exception.InnerException.Message)"
}
