<#PSScriptInfo
.VERSION 1.0
.GUID d4b03f9b-ddb6-420b-8417-d390a89cba50
.AUTHOR Tomas Kouba (S&T CZ)
.COMPANYNAME S&T CZ
.COPYRIGHT (c) 2022 S&T CZ. All rights reserved.
.TAGS RSA MachineKeys
.LICENSEURI https://raw.githubusercontent.com/sntcz/Clear-MachineKeys/main/LICENSE
.PROJECTURI https://github.com/sntcz/Clear-MachineKeys
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
#>

<#
.SYNOPSIS
Clean (move or delete) Machine Key files from RSA MachineKeys folder.
 
.DESCRIPTION
A large number of files are found in the operating system's Machine Keys folder 
(typically C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys). These files may consume excessive disk space 
on the application server which can adversely affect operation of services or applications hosted on the server.

Cleaning respects well-known keys and existing machine keys from machine key store.

You have been WARNED, use at your own RISK.

.PARAMETER Path
File path to the keys folder exhibiting this issue. For example:
   C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys (default value)
   C:\ProgramData\Microsoft\Crypto\RSA\S-1-5-18
   C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\Microsoft\Crypto\RSA\S-1-5-19
   C:\Windows\ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\Crypto\RSA\S-1-5-20
   C:\Windows\ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\SystemCertificates\Request\Certificates
   C:\Users\All Users\Microsoft\Crypto\RSA\MachineKeys (on Windows 10 same as C:\ProgramData\...)
   C:\Users\All Users\Microsoft\Crypto\RSA\S-1-5-18 (on Windows 10 same as C:\ProgramData\...)

.PARAMETER CreatedBefore
Defines retention period and takes value in days. Only files created before 
the specified time are considered for deletion or moving. Default value is 90 days.

.PARAMETER Delete
Files are deleted rather than moved. Moving files allowing simple way to restore them 
if any issues are observed. Files are moved to $MovePath folder. Use this
parameter carefully.

.PARAMETER LimitFiles
Limit processed files to max count. Files which cannot be moved or deleted are not counted.

.PARAMETER LimitErrors
Stop process after limited errors.

.PARAMETER AsUser
Exclude user private keys too. Experimental feature.

.PARAMETER MovePath
Destination path for backup. Default value is $Path\_saved.

.INPUTS
None.

.OUTPUTS
None. 
 
.EXAMPLE
C:\PS> .\Clear-MachineKeys.ps1
 
Description
-----------
This command move all possible keys from default folder older than 90 days.
 
.EXAMPLE
C:\PS> .\Clear-MachineKeys.ps1 -LimitFiles 100 -Delete
 
Description
-----------
This command delete 100 keys from default folder older than 90 days.
              
.NOTES
Version : 1.0, 2022-05-05
File Name : Clear-MachineKeys.ps1
Requires : PowerShell
 
.LINK
https://social.msdn.microsoft.com/Forums/en-US/35176c80-3199-4df7-a2bf-9124d31e3621
https://port135.com/remove-older-files-machinekeys/
https://kb.vmware.com/s/article/82553

#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Move')]
    Param(
        [Parameter(Mandatory=$False,ValueFromPipeline=$False,ValueFromPipelineByPropertyName=$False)]
        [string]$Path = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys",
        [Parameter(Mandatory=$False,ValueFromPipeline=$False,ValueFromPipelineByPropertyName=$False)]
        [int]$CreatedBefore = 90,
        [Parameter(ParameterSetName='Delete',Mandatory=$False,ValueFromPipelineByPropertyName=$False)]
        [switch]$Delete,
        [Parameter(Mandatory=$False,ValueFromPipeline=$False,ValueFromPipelineByPropertyName=$False)]
        [int]$LimitFiles = [Int32]::MaxValue,
        [Parameter(Mandatory=$False,ValueFromPipeline=$False,ValueFromPipelineByPropertyName=$False)]
        [int]$LimitErrors = [Int32]::MaxValue,
        [Parameter(Mandatory=$False,ValueFromPipelineByPropertyName=$False)]
        [switch]$AsUser,
        [Parameter(ParameterSetName='Move',Mandatory=$False,ValueFromPipelineByPropertyName=$False)]
        [string]$MovePath = ""
    )

PROCESS {

    # Get container names for stored certificates
    function Get-StoreCertificates ($StoreName) {
        foreach ($Store in (Get-ChildItem $StoreName)) {
            Write-Verbose "Store: $($StoreName)\$($Store.Name)"
            try {
                foreach ($Key in (Get-ChildItem "$($StoreName)\$($Store.Name)" -ErrorAction SilentlyContinue)) {
                    $ContainerName = $Key.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
                    if (-not [string]::IsNullOrWhiteSpace($ContainerName)) {
                        Write-Debug "Container: $ContainerName "
                        Write-Output $ContainerName
                    }
                }
            }
            catch {
                Write-Warning "Store '$($StoreName)\$($Store.Name)' error: $_"
            }
        }
    }

    try {
        $machineGuid = (Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography -Name MachineGuid).MachineGuid
        Write-Verbose "Machine GUID: $($machineGuid)"    

        $lastWrite = (Get-Date).AddDays(-$CreatedBefore)
        $lastBoot = (Get-CimInstance -ComputerName localhost -Class CIM_OperatingSystem -ErrorAction Ignore).LastBootUpTime

        if ($lastBoot.AddDays(-1) -gt $lastWrite) {
            Write-Host "Last boot was $lastBoot, but you want to process files before $lastWrite. Try use '-CreatedBefore $(((Get-Date) - $lastBoot).Days + 1)'"
        }

        # Well-known exclusions
        $excludeFiles = @(
            "6de9cb26d2b98c01ec4e9e8b34824aa2_$machineGuid", # iisConfigurationKey
            "d6d986f09a1ee04e24c949879fdb506c_$machineGuid", # NetFrameworkConfigurationKey
            "76944fb33636aeddb9590521c2e8815a_$machineGuid", # iisWasKey
            "c2319c42033a5ca7f44e731bfd3fa2b5_$machineGuid", # Microsoft Internet Information Server
            "bedbf0b4da5f8061b6444baedf4c00b1_$machineGuid", # WMSvc Certificate Key Container
            "7a436fe806e483969f48a894af2fe9a1_$machineGuid", # MS IIS DCOM Server
            "f686aace6942fb7f7ceb231212eef4a4_$machineGuid"  # TSSecKeySet1
            )
        Write-Progress -Activity "Clear-MachineKeys" -Status "Enumeratin exclusions"
        # Add exclusions from local machine cert store
        $excludeFiles = $excludeFiles + @(Get-StoreCertificates 'Cert:\LocalMachine') 
        if ($AsUser) {
            # Add exclusions from current user cert store
            $excludeFiles = $excludeFiles + @(Get-StoreCertificates 'Cert:\CurrentUser')
        }
        # Define and initialize counters
        $processedFiles = 0
        $errorFiles = 0
        $skippedFiles = 0
        # Initialize move path and create folder it is not exist
        if (-not $Delete) {
            if ($MovePath.Length -eq 0) {
                $MovePath = Join-Path $Path "_saved"
            }
            Write-Verbose "Move path:  $MovePath"
            if (-not (Test-Path $MovePath)) {
                New-Item -Path $MovePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
        }
        
        Write-Progress -Activity "Clear-MachineKeys" -Status "Loading directory contents"
        # Process folder
        foreach ($fileName in [IO.Directory]::EnumerateFiles($Path)) { 
            # Stop process on limits
            if (($LimitFiles -ne 0 -and $processedFiles -ge $LimitFiles) -or ($LimitErrors -ne 0 -and $errorFiles -ge $LimitErrors)) {
                break
            }
            $file = Get-Item $fileName
            # Detect age of file
            if ($file.LastWriteTime -le $lastWrite -and -not $excludeFiles.Contains($file.Name)) {
                if ($WhatIfPreference) { 
                    # WhatIf switch is on.
                    Write-Host "WhatIf: I will $(if($Delete){"delete"}else{"move"}) $($file.Name)" -ForegroundColor Yellow
                    $processedFiles++
                } else {
                    # WhatIf switch is off.
                    if($PSCmdlet.ShouldProcess($file.Name,  $(if($Delete){"DELETE"}else{"MOVE"}))){
                        if ($Delete) {
                            try {
                                $file.Delete()
                                $processedFiles++  
                            }
                            catch {
                                Write-Warning $_
                                $errorFiles++
                            }
                        }
                        else {
                            try {
                                $file.MoveTo($(Join-Path $MovePath $file.Name))
                                $processedFiles++  
                            }
                            catch {
                                Write-Warning "$($file.name): $_"
                                $errorFiles++
                            }
                        }
                    }
                }
                $currentOperation = "$(if($Delete){"Delete"}else{"Move"}): $($file.Name)"
            }
            else {
                Write-Debug "Skip: $($file.Name)"
                $currentOperation = "Skip: $($file.Name)"
                $skippedFiles++
            }
            if ((($processedFiles + $skippedFiles) % 100) -eq 0) {
                if ($LimitFiles -lt [Int32]::MaxValue) {
                    Write-Progress -Activity "Clear-MachineKeys" -Status "$(if($Delete){"Deleting files"}else{"Moving files"}): $($processedFiles)/$($LimitFiles), Skipped files: $skippedFiles" -CurrentOperation $currentOperation -PercentComplete ($processedFiles/$LimitFiles*100)
                }
                else {
                    Write-Progress -Activity "Clear-MachineKeys" -Status "$(if($Delete){"Deleting files"}else{"Moving files"}): $processedFiles, Skipped files: $skippedFiles," -CurrentOperation $currentOperation
                }
            }
        }
        Write-Progress -Activity "Clear-MachineKeys" -Status "Done" -Completed
        if ($WhatIfPreference) { 
            Write-Host "WhatIf: I will $(if($Delete) {'delete'} else {'move'}) $ProcessedFiles files. Skip $skippedFiles files." -ForegroundColor Yellow
        } else {
            Write-Host "$processedFiles files $(if($Delete) {'Deleted'} else {'moved'}) and $errorFiles errors. Skipped $skippedFiles files." -ForegroundColor $(if ($errorFiles -eq 0) {"Green"} else {"Red"})
        }        
    }
    catch {
        Write-Error $_
    }
}
