Clear-Host
Write-Host " 
    ██████╗██████╗ ██╗███╗   ███╗███████╗██╗     ██╗███████╗███████╗
   ██╔════╝██╔══██╗██║████╗ ████║██╔════╝██║     ██║██╔════╝██╔════╝
   ██║     ██████╔╝██║██╔████╔██║█████╗  ██║     ██║█████╗  █████╗  
   ██║     ██╔══██╗██║██║╚██╔╝██║██╔══╝  ██║     ██║██╔══╝  ██╔══╝  
   ╚██████╗██║  ██║██║██║ ╚═╝ ██║███████╗███████╗██║██║     ███████╗
    ╚═════╝╚═╝  ╚═╝╚═╝╚═╝     ╚═╝╚══════╝╚══════╝╚═╝╚═╝     ╚══════╝" -ForegroundColor Red
Write-Host "          -------------------- " -NoNewline -ForegroundColor Blue
Write-Host "BAM PARSER" -NoNewline -ForegroundColor Red
Write-Host " --------------------" -ForegroundColor Blue
Write-Host "`n"
function Get-Bam {
    $ErrorActionPreference = "SilentlyContinue"

    if (!(Get-PSDrive -Name HKLM -PSProvider Registry)) {
        try {
            New-PSDrive -Name HKLM -PSProvider Registry -Root HKEY_LOCAL_MACHINE
        }
        catch {
            Write-Warning "Error Mounting HKLM"
        }
    }

    $bamPaths = @("bam", "bam\State")
    $userSIDs = foreach ($path in $bamPaths) {
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$path\UserSettings\" |
        Select-Object -ExpandProperty PSChildName
    }

    $tzInfo = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation"
    $bias = -1 * [convert]::ToInt32($tzInfo.ActiveTimeBias)

    $registryPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\bam\UserSettings\",
        "HKLM:\SYSTEM\CurrentControlSet\Services\bam\state\UserSettings\"
    )

    $results = @()

    foreach ($sid in $userSIDs) {
        foreach ($basePath in $registryPaths) {
            $fullPath = "$basePath$SID"
            $props = (Get-Item -Path $fullPath).Property
            if (!$props) { continue }

            foreach ($item in $props) {
                $data = (Get-ItemProperty -Path $fullPath).$item

                if ($data.Length -eq 24) {
                    $hex = [System.BitConverter]::ToString($data[7..0]) -replace "-", ""
                    $fileTime = [Convert]::ToInt64($hex, 16)
                    $userTime = (Get-Date ([DateTime]::FromFileTimeUtc($fileTime)).AddMinutes($bias) -Format "yyyy-MM-dd HH:mm:ss")

                    $isValid = ((Split-Path -Path $item | ConvertFrom-String -Delimiter "\\").P3) -match '\d'
                    if ($isValid) {
                        $appPath = Join-Path -Path "C:" -ChildPath $item.Remove(0, 23)

                        $status = ""
                        $color = "Gray"

                        if (Test-Path $appPath) {
                            $signature = Get-AuthenticodeSignature -FilePath $appPath
                            if ($signature.Status -ne "Valid") {
                                switch ($signature.Status) {
                                    "NotSigned" { $status = "Unsigned"; $color = "Red" }
                                    default { $status = "$($signature.Status)"; $color = "DarkRed" }
                                }
                                $results += [PSCustomObject]@{
                                    Status    = $status
                                    Timestamp = $userTime
                                    Path      = $appPath
                                    Color     = $color
                                }
                            }
                        }
                        else {
                            $status = "Deleted"
                            $color = "DarkRed"

                            $results += [PSCustomObject]@{
                                Status    = $status
                                Timestamp = $userTime
                                Path      = $appPath
                                Color     = $color
                            }
                        }


                    }
                }
            }
        }
    }


    Write-Host ("{0,-15}  {1,-19}  {2,-70}" -f "Status", "Timestamp", "Path") -ForegroundColor Blue
    Write-Host ("{0,-15}  {1,-19}  {2,-70}" -f ("-" * 15), ("-" * 19), ("-" * 70))

    foreach ($entry in $results) {
        Write-Host ("{0,-15}  {1,-19}  {2,-70}" -f $entry.Status, $entry.Timestamp, $entry.Path) -ForegroundColor $entry.Color
    }
}

Get-Bam
