#Requires -Version 5.1
<#
.SYNOPSIS
  Keep Hafiz Auth on OTP codes (not magic links).

IMPORTANT (free Supabase tier):
  - Custom email templates REQUIRE custom SMTP to stay applied.
  - Clearing SMTP resets templates back to magic-link defaults.
  - Never disable SMTP/hook without re-running this script.

.PARAMETER AccessToken
  Supabase personal access token (sbp_...). Defaults to $env:SUPABASE_ACCESS_TOKEN.

.PARAMETER ResendApiKey
  Resend API key (re_...). Defaults to $env:RESEND_API_KEY.

.PARAMETER ProjectRef
  Defaults to qlqzdtphwmoohqgqftuv.

.PARAMETER FromEmail
  Defaults to "Hafiz <onboarding@resend.dev>". After domain verify, use an address on that domain.
#>
param(
  [string]$AccessToken = $env:SUPABASE_ACCESS_TOKEN,
  [string]$ResendApiKey = $env:RESEND_API_KEY,
  [string]$ProjectRef = "qlqzdtphwmoohqgqftuv",
  [string]$FromEmail = "Hafiz <onboarding@resend.dev>"
)

if (-not $AccessToken) { throw "Set SUPABASE_ACCESS_TOKEN or pass -AccessToken" }
if (-not $ResendApiKey) { throw "Set RESEND_API_KEY or pass -ResendApiKey" }

$uri = "https://api.supabase.com/v1/projects/$ProjectRef/config/auth"
$headers = @{
  Authorization = "Bearer $AccessToken"
  Accept = "application/json"
  "Content-Type" = "application/json; charset=utf-8"
}

$hookFile = Join-Path $env:TEMP "hafiz_hook_secret_$ProjectRef.txt"
if (-not (Test-Path $hookFile) -or -not (Get-Content $hookFile -Raw).Trim()) {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  [System.IO.File]::WriteAllText($hookFile, [Convert]::ToBase64String($bytes))
}
$hookSecret = "v1,whsec_$((Get-Content $hookFile -Raw).Trim())"

$env:SUPABASE_ACCESS_TOKEN = $AccessToken
supabase secrets set --project-ref $ProjectRef `
  "RESEND_API_KEY=$ResendApiKey" `
  "AUTH_EMAIL_FROM=$FromEmail" `
  "SEND_EMAIL_HOOK_SECRET=$hookSecret" | Out-Host

supabase functions deploy auth-send-email --project-ref $ProjectRef --no-verify-jwt | Out-Host

$otpHtml = '<h2>Hafiz verification code</h2><p><b>Enter this 6-digit code in the Hafiz app.</b> Do not open any link.</p><p style="font-size:40px;font-weight:bold;letter-spacing:12px;font-family:monospace;text-align:center;">{{ .Token }}</p><p>Expires in one hour.</p>'

$payload = @{
  site_url = "https://$ProjectRef.supabase.co"
  uri_allow_list = "https://$ProjectRef.supabase.co/**"
  smtp_host = "smtp.resend.com"
  smtp_port = "465"
  smtp_user = "resend"
  smtp_pass = $ResendApiKey
  smtp_admin_email = "onboarding@resend.dev"
  smtp_sender_name = "Hafiz"
  hook_send_email_enabled = $true
  hook_send_email_uri = "https://$ProjectRef.supabase.co/functions/v1/auth-send-email"
  hook_send_email_secrets = $hookSecret
  mailer_subjects_magic_link = "Hafiz verification code"
  mailer_templates_magic_link_content = $otpHtml
  mailer_subjects_confirmation = "Hafiz verification code"
  mailer_templates_confirmation_content = $otpHtml
  mailer_subjects_recovery = "Hafiz verification code"
  mailer_templates_recovery_content = $otpHtml
}

$tmp = Join-Path $env:TEMP "hafiz_auth_otp_$ProjectRef.json"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tmp, ($payload | ConvertTo-Json -Depth 5), $utf8)
Invoke-WebRequest -Method Patch -Uri $uri -Headers $headers -InFile $tmp -UseBasicParsing | Out-Null

$auth = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $AccessToken"; Accept = "application/json" }
$ok = $auth.hook_send_email_enabled -eq $true -and
  $auth.smtp_host -eq "smtp.resend.com" -and
  [string]$auth.mailer_templates_magic_link_content -match "Token" -and
  [string]$auth.mailer_templates_magic_link_content -notmatch "ConfirmationURL"

if (-not $ok) { throw "Auth OTP configuration verification failed" }

Write-Host "OK: SMTP + OTP templates + send-email hook are active."
Write-Host "NOTE: With onboarding@resend.dev, Resend only delivers to the Resend account email until a domain is verified."
