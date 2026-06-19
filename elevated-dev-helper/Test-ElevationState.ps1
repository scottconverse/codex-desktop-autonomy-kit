$ErrorActionPreference = "Stop"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$integritySid = $identity.Groups | Where-Object { $_.Value -like "S-1-16-*" } | Select-Object -First 1
$integrity = if ($integritySid) {
    switch ($integritySid.Value) {
        "S-1-16-4096" { "Low Mandatory Level" }
        "S-1-16-8192" { "Medium Mandatory Level" }
        "S-1-16-8448" { "Medium Plus Mandatory Level" }
        "S-1-16-12288" { "High Mandatory Level" }
        "S-1-16-16384" { "System Mandatory Level" }
        default { $integritySid.Value }
    }
} else {
    "Unknown"
}

[PSCustomObject]@{
    User = $identity.Name
    Elevated = $isAdmin
    Integrity = $integrity
    ProcessId = $PID
    PowerShell = $PSVersionTable.PSVersion.ToString()
} | Format-List
