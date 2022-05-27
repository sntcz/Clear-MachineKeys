# Clear-MachineKeys

The `MachineKeys` folder stores certificate key pairs for computer and users. It is used by the Crypto Service Provider,
so many applications (including IIs or Internet Explorer) uses this folder for storing certificate key pairs. Because of
a permission or application code related issue, this folder may fill up with thousands of files in a short time.

The correct solution is to fix permission or code issue so that the certificate key pairs in this folder are automatically
removed. As a temporary solution or as a fix after permanent solution this script could remove old files from the `MachineKeys`
folder.

`Clear-MachineKeys` scripts scans folder passed as parameter and move or delete old unused private key containers in it.
So the script excludes following key containers:
    1. Containers with well-known names
    2. Keys found in the machine certificate store
    3. Key containers created recently (last write time)

**NOTE:** Use this script at your own risk. Deleting keys that are in use, may create some issues.

This script must be executed with administrative rights (Run As Administrator).

## Script parameters

1. **Path** - File path to the keys folder exhibiting this issue. For example:
   * C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys (default value)
   * C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18
   * C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\Microsoft\Crypto\RSA\S-1-5-19
   * C:\Windows\ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\Crypto\RSA\S-1-5-20
   * C:\Windows\ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\SystemCertificates\Request\Certificates
   * C:\Users\All Users\Microsoft\Crypto\RSA\MachineKeys (on Windows 10 same as C:\ProgramData\...)
   * C:\Users\All Users\Microsoft\Crypto\RSA\S-1-5-18 (on Windows 10 same as C:\ProgramData\...)
2. **CreatedBefore** - Defines retention period and takes value in days. Only files created before the specified time are considered for deletion or moving. Default value is 90 days.
3. **Delete** - Files are deleted rather than moved. Moving files allowing simple way to restore them if any issues are observed. Files are moved to $Path\_saved folder. Use this parameter carefully.
4. **LimitFiles** - Limit processed files to max count. Files which cannot be moved or deleted are not counted.
5. **LimitErrors** - Stop process after limited errors.
6. **AsUser** - Exclude current user private keys too. Experimental feature.
7. **MovePath** - Destination path for backup. Default value is *Path*\_saved, but can be overriden by this parameter.
8. **WhatIf** - Dry run.

## Periodic execution

You may use Powershell scheduled jobs

```powershell
$options = New-ScheduledJobOption -WakeToRun -StartIfIdle -MultipleInstancePolicy IgnoreNew -RunElevated
$trigger = New-JobTrigger --Weekly -DaysOfWeek Monday -At "00:30 AM" -RandomDelay 01:00:00
Register-ScheduledJob -Name "Clear-MachineKeys" -FilePath "<<path to the script>>\Clear-MachineKeys.ps1" -Trigger $trigger -ScheduledJobOption $options
```

## Usefull links

* <https://port135.com/remove-older-files-machinekeys/>
* <https://docs.microsoft.com/en-us/troubleshoot/windows-server/windows-security/default-permissions-machinekeys-folders>
* <https://techcommunity.microsoft.com/t5/iis-support-blog/machinekeys-folder-fills-up-quickly/ba-p/1608008>
* <https://kb.vmware.com/s/article/82553>
* <https://social.msdn.microsoft.com/Forums/en-US/35176c80-3199-4df7-a2bf-9124d31e3621>
