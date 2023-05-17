Import-Module -Name AWSPowerShell
Function Get-NtpSyncStatus {
    $ntpStatus = Get-Service w32time -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Status
    if ($ntpStatus -eq 'Running') {
        $statusOutput = w32tm /query /status
        $metrics = @{
            "LeapIndicator" = ($statusOutput | Select-String -Pattern '^Leap Indicator:\s+(\d)').Matches.Groups[1].Value
            "Stratum" = ($statusOutput | Select-String -Pattern '^Stratum:\s+(\d+)').Matches.Groups[1].Value
            "Precision" = ($statusOutput | Select-String -Pattern '^Precision:\s+(-?\d+)').Matches.Groups[1].Value
            "RootDelay" = ($statusOutput | Select-String -Pattern '^Root Delay:\s+(.*)').Matches.Groups[1].Value
            "RootDispersion" = ($statusOutput | Select-String -Pattern '^Root Dispersion:\s+(.*)').Matches.Groups[1].Value
            "LastSyncTime" = ($statusOutput | Select-String -Pattern '^Last Successful Sync Time:\s+(.+)').Matches.Groups[1].Value
            "PollInterval" = ($statusOutput | Select-String -Pattern '^Poll Interval:\s+(\d+)').Matches.Groups[1].Value
        }
        $dimensions = @{
            "Source" = ($statusOutput | Select-String -Pattern '^Source:\s+(.+)').Matches.Groups[1].Value
            "ReferenceId" = ($statusOutput | Select-String -Pattern '^ReferenceId:\s+(.+)').Matches.Groups[1].Value
        }
        $ntpStatus = @{
            "Status" = "Running"
            "Metrics" = $metrics
            "Dimensions" = $dimensions
        }
    }
    else {
        $ntpStatus = @{
            "Status" = "Not Running"
            "Metrics" = @{}
            "Dimensions" = @{}
        }
    }
    return $ntpStatus
}
$ntpSyncStatus = Get-NtpSyncStatus
$referenceId = [regex]::Match($ntpSyncStatus.Dimensions.ReferenceId, "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}").Value
$source = $ntpSyncStatus.Dimensions.Source.Split(',')[0].Trim()
$rootDispersion = [double]::Parse($ntpSyncStatus.metrics.RootDispersion.Trim('s'))
$precision = [int]$ntpSyncStatus.metrics.Precision
$pollInterval = [int]$ntpSyncStatus.metrics.PollInterval
$stratum = [int]$ntpSyncStatus.metrics.Stratum
$lastSyncTimeFormat = 'dd/MM/yyyy h:mm:ss tt'
$lastSyncTime = [DateTime]::MinValue
[DateTime]::TryParseExact($ntpSyncStatus.metrics.LastSyncTime, $lastSyncTimeFormat, $null, [System.Globalization.DateTimeStyles]::None, [ref]$lastSyncTime)
$rootDelay = [double]::Parse($ntpSyncStatus.metrics.RootDelay.Trim('s'))
$leapIndicator = [int]$ntpSyncStatus.metrics.LeapIndicator
$preclockErrorBound = $lastSyncTime.AddSeconds(0.5 * $rootDelay + $rootDispersion)
$clockErrorBound = [Math]::Round(([DateTime]::Now - $lastSyncTime).TotalSeconds)
$leapIndicator = [int]$ntpSyncStatus.metrics.LeapIndicator
$upstreamTime = & w32tm /stripchart /computer:169.254.169.123 /samples:1 /dataonly
$match = [regex]::Match($upstreamTime, '(\d{2}:\d{2}:\d{2}),\s+([-+]?\d+\.\d+s)')
$timeDifference = [double]$match.Groups[2].Value.Trim('s')
$lastSync = [Math]::Round(([DateTime]::Now - $lastSyncTime).TotalSeconds)
$customMetricData = @(
    @{
        MetricName = “RootDispersion”
        Value = $rootDispersion
        Unit = “Seconds”
    }
    @{
        MetricName = “Precision”
        Value = $precision
        Unit = “Count”
    }
    @{
        MetricName = “PollInterval”
        Value = $pollInterval
        Unit = “Count”
    }
    @{
        MetricName = “Stratum”
        Value = $stratum
        Unit = “Count”
    }
    @{
        MetricName = “RootDelay”
        Value = $rootDelay
        Unit = “Seconds”
    }
    @{
        MetricName = “LeapIndicator”
        Value = $leapIndicator
        Unit = “Count”
    }
    @{
        MetricName = “ClockErrorBound”
        Value = $clockErrorBound
        Unit = “Milliseconds”
    }
    @{
        MetricName = “TimeDrift”
        Value = $timeDifference.TotalMilliseconds
        Unit = “Milliseconds”
    }
    @{
        MetricName = “LastSyncAgo”
        Value = $lastSync
        Unit = "Seconds"
    }
)
# Send the custom metric data to CloudWatch
Write-CWMetricData -Namespace “Time” -MetricData $customMetricData


# # Write out to shell for debug
# Write-Host "ReferenceId: $referenceId"
# Write-Host "Source: $source"
# Write-Host "RootDispersion: $rootDispersion"
# Write-Host "Precision: $precision"
# Write-Host "PollInterval: $pollInterval"
# Write-Host "Stratum: $stratum"
# Write-Host "RootDelay: $rootDelay"
# Write-Host "LeapIndicator: $leapIndicator"
# Write-Host "Clock Error Bound: $clockErrorBound"
# Write-Host "Drift: $timeDifference"
# Write-Host "Last Sync: $lastSync"