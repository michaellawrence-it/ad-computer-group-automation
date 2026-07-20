Import-Module ActiveDirectory
$log = "C:\Scripts\GroupScriptLog.txt"
Add-Content $log "----- Script Started $(Get-Date) -----"
try {
    $event = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4741
        StartTime = (Get-Date).AddMinutes(-5)
    } -ErrorAction Stop | Select-Object -First 1
    if (-not $event) {
        throw "No recent computer creation event (4741) found."
    }
    $xml = [xml]$event.ToXml()
    $samName = (($xml.Event.EventData.Data |
        Where-Object { $_.Name -eq "SamAccountName" }).'#text')
    Add-Content $log "SAM Name Found: $samName"
    if ([string]::IsNullOrWhiteSpace($samName)) {
        throw "SamAccountName was blank."
    }
    $computer = $samName -replace '\$$', ''
    Add-Content $log "Computer: $computer"
    $computerObj = Get-ADComputer -Identity $computer -ErrorAction Stop
    $groups = @(
        "LAPS",
        "Intune-Enrollment",
        "OneDriveComputers",
        "OneDrive-PublicFolder",
        "Remove-Users-From-LocalAdmingGrp"
    )
    foreach ($group in $groups) {
        try {
            Add-Content $log "Adding $computer to $group"
            $groupObj = Get-ADGroup -Identity $group -ErrorAction Stop
            Add-ADGroupMember -Identity $groupObj -Members $computerObj -ErrorAction Stop
            Add-Content $log "SUCCESS: Added $computer to $group"
        }
        catch {
            Add-Content $log "ERROR in ${group}: $($_.Exception.Message)"
        }
    }
    Add-Content $log "Script finished"
}
catch {
    Add-Content $log "FATAL ERROR: $($_.Exception.Message)"
}
