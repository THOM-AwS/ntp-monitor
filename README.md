# ntp-monitor
An NTP monitor for cloudwatch written in PowerShell (yuck)

Set up a monitor for W32tm that can be added to your Windows EC2, where it can be configured to run on an interval and push metrics to your Cloudwatch for easy monitoring.

Install and configure the scheduled task to run the PS1 script at whatever interval you need.