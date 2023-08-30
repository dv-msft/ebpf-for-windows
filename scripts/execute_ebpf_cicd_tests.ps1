﻿# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param ([parameter(Mandatory=$false)][string] $AdminTarget = "TEST_VM",
       [parameter(Mandatory=$false)][string] $StandardUserTarget = "TEST_VM_STANDARD",
       [parameter(Mandatory=$false)][string] $LogFileName = "TestLog.log",
       [parameter(Mandatory=$false)][string] $WorkingDirectory = $pwd.ToString(),
       [parameter(Mandatory=$false)][string] $TestExecutionJsonFileName = "test_execution.json",
       [parameter(Mandatory=$false)][bool] $Coverage = $false,
       [parameter(Mandatory=$false)][bool] $RunKmStressTestsOnly = $false,
       [parameter(Mandatory=$false)][bool] $RestartExtension = $false,
       [parameter(Mandatory=$false)][string] $SelfHostedRunnerName)

Push-Location $WorkingDirectory

$AdminTestVMCredential = Get-StoredCredential -Target $AdminTarget -ErrorAction Stop
$StandardUserTestVMCredential = Get-StoredCredential -Target $StandardUserTarget -ErrorAction Stop

# Load other utility modules.
Import-Module .\common.psm1 -Force -ArgumentList ($LogFileName) -WarningAction SilentlyContinue
Import-Module .\vm_run_tests.psm1  -Force -ArgumentList ($AdminTestVMCredential.UserName, $AdminTestVMCredential.Password, $StandardUserTestVMCredential.UserName, $StandardUserTestVMCredential.Password, $WorkingDirectory, $LogFileName) -WarningAction SilentlyContinue

# Read the test execution json.
$Config = Get-Content ("{0}\{1}" -f $PSScriptRoot, $TestExecutionJsonFileName) | ConvertFrom-Json
$VMList = $Config.VMMap.$SelfHostedRunnerName

# Run tests on test VMs.
foreach ($VM in $VMList) {
    Invoke-CICDTestsOnVM `
        -VMName $VM.Name `
        -Coverage $Coverage `
        -RunKmStressTestsOnly $RunKmStressTestsOnly `
        -RestartExtension $RestartExtension
}

# This script is used to execute the regular kernel mode tests as well as the scheduled kernel mode stress tests. The
# required behavior is selected by the $RunKmStressTestsOnly parameter which is set to 'true' only for the scheduled
# runs.  The other tests i.e., Invoke-XDPTestsOnVM, Invoke-ConnectRedirectTestsOnVM and
# Invoke-ConnectRedirectTestsOnVM are already handled by other jobs, so re-executing them again along with the stress
# tests is redundant.
if ($RunKmStressTestsOnly -eq $false) {

    # Run XDP Tests.
    Invoke-XDPTestsOnVM $Config.Interfaces $VMList[0].Name

    # Run Connect Redirect Tests.
    Invoke-ConnectRedirectTestsOnVM $Config.Interfaces $Config.ConnectRedirectTest `
        -UserType "Administrator" $VMList[0].Name
    Invoke-ConnectRedirectTestsOnVM $Config.Interfaces $Config.ConnectRedirectTest `
        -UserType "StandardUser" $VMList[0].Name
}

# Stop eBPF components on test VMs.
foreach ($VM in $VMList) {
    Stop-eBPFComponentsOnVM -VMName $VM.Name
}

Pop-Location