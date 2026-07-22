#Requires -Version 5.1
<#
.SYNOPSIS
  Configure Hafiz Auth for email OTP (6-digit code) via Resend SMTP + optional send-email hook.

.PARAMETER ResendApiKey
  Resend API key (re_...). Free keys can send from onboarding@resend.dev.

.PARAMETER AccessToken
  Supabase personal access token (sbp_...). Defaults to $env:SUPABASE_ACCESS_TOKEN.

.PARAMETER ProjectRef
  Defaults to qlqzdtphwmoohqgqftuv.
#>
param(
  [Parameter(Mandatory = $true)][string]$ResendApiKey,
  [string]$AccessToken = $env:SUPABASE_ACCESS_TOKEN,
  [string]$ProjectRef = "qlqzdtphwmoohqgqftuv",
  [string]$FromEmail = "onboarding@resend.dev",
  [string]$FromName = "Hafiz"
)

if (-not $AccessToken) {
  throw "Set SUPABASE_ACCESS_TOKEN or pass -AccessToken"
}

$uri = "https://api.supabase.com/v1/projects/$ProjectRef/config/auth"
$headers = @{
  Authorization = "Bearer $AccessToken"
  Accept = "application/json"
  "Content-Type" = "application/json; charset=utf-8"
}

$magicHtml = @"
<h2>Your verification code</h2>
<p>Enter this code in the Hafiz app to continue:</p>
<p style="font-size:32px;font-weight:bold;letter-spacing:8px;font-family:monospace;">{{ .Token }}</p>
<p>This code expires in one hour. If you did not request it, you can ignore this email.</p>
"@

$confirmHtml = @"
<h2>Your verification code</h2>
<p>Enter this code in the Hafiz app to verify your email:</p>
<p style="font-size:32px;font-weight:bold;letter-spacing:8px;font-family:monospace;">{{ .Token }}</p>
<p>This code expires in one hour. If you did not request it, you can ignore this email.</p>
"@

$body = @{
  smtp_host = "smtp.resend.com"
  smtp_port = "465"
  smtp_user = "resend"
  smtp_pass = $ResendApiKey
  smtp_admin_email = $FromEmail
  smtp_sender_name = $FromName
  mailer_subjects_magic_link = "Hafiz verification code"
  mailer_templates_magic_link_content = $magicHtml
  mailer_subjects_confirmation = "Hafiz verification code"
  mailer_templates_confirmation_content = $confirmHtml
  mailer_otp_length = 6
  mailer_autoconfirm = $true
  site_url = "https://$ProjectRef.supabase.co"
  uri_allow_list = "https://$ProjectRef.supabase.co/**,https://$ProjectRef.supabase.co/functions/v1/**"
  # Prefer SMTP templates; disable hook unless you also set RESEND_API_KEY on the function.
  hook_send_email_enabled = $false
} | ConvertTo-Json -Depth 5

$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$resp = Invoke-WebRequest -Method PATCH -Uri $uri -Headers $headers -Body $bytes -UseBasicParsing
$j = $resp.Content | ConvertFrom-Json

Write-Host "Configured Auth OTP email."
Write-Host "site_url=$($j.site_url)"
Write-Host "smtp_host=$($j.smtp_host)"
Write-Host "otp_length=$($j.mailer_otp_length)"
Write-Host "magic_has_token=$(([string]$j.mailer_templates_magic_link_content) -match 'Token')"
Write-Host "hook_enabled=$($j.hook_send_email_enabled)"
Write-Host ""
Write-Host "Also set the Edge Function secret (optional if using SMTP only):"
Write-Host "  supabase secrets set RESEND_API_KEY=$ResendApiKey --project-ref $ProjectRef"
