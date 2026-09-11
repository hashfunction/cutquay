# Disposable Windows CI installation qualification for CutQuay.
# Copyright 2026 Trieflow LLC. MIT licensed.
# Installation-flow structure adapted from ReticleQuay's MIT helper; the full
# retained notice is in RETICLEQUAY-MIT.txt.
[CmdletBinding()]
param(
    [Parameter()][string]$Package,
    [Parameter()][string]$PackageRecord,
    [Parameter()][string]$SignTool,
    [Parameter()][string]$Output,
    [Parameter()][switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-CutQuayQualificationCore([Collections.IDictionary]$Operations) {
    $required = @(
        'Preflight','PrepareSignedCopy','Install','VerifyInstalledMedia','CaptureInstalledStderr','ActivateAndVerify','CloseCleanly','UninstallAndVerify',
        'StopOwnedProcess','RemoveOwnedPackage','RemoveTrustedCertificate','RemovePersonalCertificate','RemoveTemporaryFiles'
    )
    foreach ($name in $required) {
        if (-not $Operations.Contains($name) -or $Operations[$name] -isnot [scriptblock]) {
            throw "Missing qualification operation: $name"
        }
    }
    $primaryError = $null
    $cleanupErrors = [Collections.Generic.List[string]]::new()
    try {
        foreach ($name in @('Preflight','PrepareSignedCopy','Install','VerifyInstalledMedia','CaptureInstalledStderr','ActivateAndVerify','CloseCleanly','UninstallAndVerify')) {
            # Native tools such as SignTool emit stdout. Keep it in the host
            # log without turning this function's structured result into an array.
            & $Operations[$name] | Out-Host
        }
    } catch {
        $primaryError = $_.Exception.Message
    } finally {
        foreach ($name in @('StopOwnedProcess','RemoveOwnedPackage','RemoveTrustedCertificate','RemovePersonalCertificate','RemoveTemporaryFiles')) {
            try {
                & $Operations[$name] | Out-Host
            } catch {
                $cleanupErrors.Add("${name}: $($_.Exception.Message)")
            }
        }
    }
    return [pscustomobject][ordered]@{
        installation_qualification_passed = (-not $primaryError -and $cleanupErrors.Count -eq 0)
        primary_error = $primaryError
        cleanup_errors = @($cleanupErrors)
    }
}

function Invoke-CheckedNative([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit $LASTEXITCODE" }
}

function Get-CanonicalPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathInside([string]$Candidate, [string]$Root) {
    $candidatePath = Get-CanonicalPath $Candidate
    $rootPath = Get-CanonicalPath $Root
    return $candidatePath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
        $candidatePath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-RecordPayloadEntry([object]$Record, [string]$Relative) {
    $property = $Record.payload.PSObject.Properties[$Relative]
    if (-not $property) { throw "Installed/package module is absent from the verified payload record: $Relative" }
    return $property.Value
}

function Assert-FileMatchesRecord([string]$Path, [object]$Expected, [string]$Label) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or $item.LinkType -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "$Label is not a regular non-link file: $Path" }
    if ($item.Length -ne [int64]$Expected.bytes) { throw "$Label size differs from package record: $Path" }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$Expected.sha256).ToLowerInvariant()) { throw "$Label hash differs from package record: $Path" }
    return $hash
}

function Add-CutQuayActivationTypes {
    if ('CutQuayQualification.NativePackageProbe' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CutQuayQualification {
    [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    internal class ApplicationActivationManagerClass { }

    [ComImport, Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager {
        [PreserveSig]
        int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string arguments, uint options, out uint processId);
        [PreserveSig]
        int ActivateForFile([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr shellItemArray, [MarshalAs(UnmanagedType.LPWStr)] string verb, out uint processId);
        [PreserveSig]
        int ActivateForProtocol([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            IntPtr shellItemArray, out uint processId);
    }

    public static class ActivationBroker {
        public static uint Activate(string appUserModelId) {
            var manager = (IApplicationActivationManager)new ApplicationActivationManagerClass();
            uint processId;
            int result = manager.ActivateApplication(appUserModelId, null, 0, out processId);
            if (result < 0) Marshal.ThrowExceptionForHR(result);
            if (processId == 0) throw new InvalidOperationException("Activation broker returned process ID zero.");
            return processId;
        }
    }

    public static class NativePackageProbe {
        private const int ERROR_SUCCESS = 0;
        private const int ERROR_INSUFFICIENT_BUFFER = 122;
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
        private static extern int GetPackageFullName(IntPtr process, ref uint length, StringBuilder packageFullName);

        public static string GetFullName(IntPtr process) {
            uint length = 0;
            int first = GetPackageFullName(process, ref length, null);
            if (first != ERROR_INSUFFICIENT_BUFFER || length == 0)
                throw new InvalidOperationException("Initial GetPackageFullName returned " + first + ", expected 122.");
            var value = new StringBuilder((int)length);
            int second = GetPackageFullName(process, ref length, value);
            if (second != ERROR_SUCCESS)
                throw new InvalidOperationException("Second GetPackageFullName returned " + second + ", expected 0.");
            return value.ToString();
        }
    }
}
'@
}

function Get-WindowQualification([Diagnostics.Process]$Process, [string]$OutputDirectory) {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $root = [Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
    if (-not $root) { throw 'UI Automation could not bind the activated main window.' }
    $rootBounds = $root.Current.BoundingRectangle
    if ($root.Current.IsOffscreen -or $rootBounds.Width -le 0 -or $rootBounds.Height -le 0) { throw 'Activated main window is not visibly rendered.' }
    $topLevelWindows = [Collections.Generic.List[object]]::new()
    $processCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ProcessIdProperty, $Process.Id)
    $desktopWindows = [Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Children, $processCondition)
    for ($index = 0; $index -lt $desktopWindows.Count; $index++) {
        $window = $desktopWindows.Item($index)
        $name = [string]$window.Current.Name
        if ($name -match '(?i)unhandled exception|uncaught exception|a javascript error occurred|traceback|fatal error|script error') { throw "Error top-level surface detected: $name" }
        $topLevelWindows.Add([ordered]@{ name=$name; offscreen=[bool]$window.Current.IsOffscreen })
    }
    $items = [Collections.Generic.List[object]]::new()
    $actionable = 0
    $descendants = $root.FindAll([Windows.Automation.TreeScope]::Subtree, [Windows.Automation.Condition]::TrueCondition)
    $limit = [Math]::Min($descendants.Count, 1000)
    for ($index = 0; $index -lt $limit; $index++) {
        $element = $descendants.Item($index)
        try {
            $name = [string]$element.Current.Name
            $control = [string]$element.Current.ControlType.ProgrammaticName
            $enabled = [bool]$element.Current.IsEnabled
            $offscreen = [bool]$element.Current.IsOffscreen
            if ($name -match '(?i)unhandled exception|uncaught exception|a javascript error occurred|traceback|fatal error|script error') {
                throw "Error surface detected in activated UI: $name"
            }
            if ($enabled -and -not $offscreen -and $name -and $control -match 'ControlType\.(Button|MenuItem|Edit|ComboBox|ListItem)') {
                $actionable++
            }
            $items.Add([ordered]@{ name=$name; control_type=$control; enabled=$enabled; offscreen=$offscreen })
        } catch {
            if ($_.Exception.Message -match '^Error surface detected') { throw }
        }
    }
    $treePath = Join-Path $OutputDirectory 'accessible-window-tree.json'
    [IO.File]::WriteAllText($treePath, (($items | ConvertTo-Json -Depth 5) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $screenshotCaptured = $false
    $screenshotError = $null
    try {
        Add-Type -AssemblyName System.Drawing
        $bounds = $rootBounds
        $bitmap = [Drawing.Bitmap]::new([int][Math]::Ceiling($bounds.Width), [int][Math]::Ceiling($bounds.Height))
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen([int]$bounds.X, [int]$bounds.Y, 0, 0, $bitmap.Size)
            $bitmap.Save((Join-Path $OutputDirectory 'qualification-window.png'), [Drawing.Imaging.ImageFormat]::Png)
            $screenshotCaptured = $true
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    } catch {
        $screenshotError = $_.Exception.Message
    }
    return [ordered]@{
        accessible_elements = $items.Count
        top_level_windows = @($topLevelWindows)
        actionable_controls_verified = ($actionable -gt 0)
        actionable_control_count = $actionable
        screenshot_captured = $screenshotCaptured
        screenshot_error = $screenshotError
        startup_limited = ($actionable -eq 0)
    }
}

function Write-NewUtf8Json([string]$Path, [object]$Value) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }
}

function Update-OwnedPackageProcesses([Collections.IDictionary]$State) {
    # This identity was absent before our install. Only exact installed-path
    # Electron processes created since that install, with its actual package
    # identity, may be retained/terminated. Keep process handles against PID reuse.
    Add-CutQuayActivationTypes
    foreach ($candidate in @(Get-Process -Name CutQuay -ErrorAction SilentlyContinue)) {
        try {
            $null = $candidate.Handle
            if ($candidate.HasExited) { continue }
            if ((Get-CanonicalPath $candidate.MainModule.FileName) -ine (Get-CanonicalPath (Join-Path $State.installed.InstallLocation 'CutQuay.exe'))) { continue }
            if ($candidate.StartTime.ToUniversalTime() -lt $State.activationStarted) { throw 'A preexisting process occupies the owned package path.' }
            if ([CutQuayQualification.NativePackageProbe]::GetFullName($candidate.Handle) -cne [string]$State.installed.PackageFullName) { throw 'Owned-path process lacks expected package identity.' }
            if (-not @($State.ownedProcesses | Where-Object { $_.Id -eq $candidate.Id -and $_.StartTime -eq $candidate.StartTime }).Count) {
                $State.ownedProcesses.Add($candidate)
            }
        } catch {
            if (-not $candidate.HasExited) { throw }
        }
    }
}

function Wait-OwnedPackageExit([Collections.IDictionary]$State) {
    Update-OwnedPackageProcesses $State
    foreach ($owned in @($State.ownedProcesses)) {
        if (-not $owned.HasExited -and -not $owned.WaitForExit(10000)) { throw "Owned Electron child remains after normal close: $($owned.Id)" }
    }
}

function Test-InstalledMedia([Collections.IDictionary]$State) {
    $results = [Collections.Generic.List[object]]::new()
    foreach ($program in @('ffmpeg','ffprobe')) {
        $relative = "resources/$program.exe"
        $executable = Join-Path $State.installed.InstallLocation $relative
        $expected = Get-RecordPayloadEntry $State.record $relative
        $hash = Assert-FileMatchesRecord $executable $expected $program
        foreach ($argument in @('-version','-buildconf')) {
            $start = [Diagnostics.ProcessStartInfo]::new($executable)
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $start.ArgumentList.Add($argument)
            $State.mediaProcess = [Diagnostics.Process]::new()
            $State.mediaProcess.StartInfo = $start
            if (-not $State.mediaProcess.Start()) { throw "Installed $program failed to start." }
            $stdout = $State.mediaProcess.StandardOutput.ReadToEndAsync()
            $stderr = $State.mediaProcess.StandardError.ReadToEndAsync()
            if (-not $State.mediaProcess.WaitForExit(30000)) { throw "Installed $program $argument timed out." }
            $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
            [IO.File]::WriteAllText((Join-Path $State.output ("installed-$program" + $argument + '.log')), $text, [Text.UTF8Encoding]::new($false))
            if ($State.mediaProcess.ExitCode -ne 0) { throw "Installed $program $argument failed with $($State.mediaProcess.ExitCode)." }
            if (-not $text.Contains([string]$State.record.runtime.media.version) -or -not $text.Contains([string]$State.record.runtime.media.configuration)) { throw "Installed $program $argument version/configuration mismatch." }
            $null = Assert-FileMatchesRecord $executable $expected $program
            $results.Add([ordered]@{ executable=$relative; sha256=$hash; argument=$argument; exit_code=$State.mediaProcess.ExitCode; version=$State.record.runtime.media.version; configuration_verified=$true })
            $State.mediaProcess.Dispose()
            $State.mediaProcess = $null
        }
    }
    return $results.ToArray()
}

function Invoke-CutQuayInstallQualification([string]$PackagePath, [string]$RecordPath, [string]$SignToolPath, [string]$OutputPath) {
    $state = [ordered]@{
        package = $null; record = $null; output = $null; temporary = $null; signedCopy = $null
        publicCertificate = $null; certificate = $null; trustedCertificate = $null; trustAttempted = $false
        installed = $null; installedByUs = $false; process = $null
        installAttempted = $false; brokerProcessId = 0
        addCompleted = $false; ownedPackageFullName = $null
        preflightPackageFullNames = @(); residualPackageFullNames = @()
        unsignedPackageSha256 = $null; signedPackageSha256 = $null; signTool = $null
        aumid = $null; processPackageFullName = $null; modules = @(); window = $null
        executableSha256 = $null; media = @(); ownedProcesses = [Collections.Generic.List[Diagnostics.Process]]::new(); activationStarted = $null; mediaProcess = $null
        diagnosticPackageFullName = $null; diagnosticStderr = $null
        diagnosticCleanClose = $false; cleanClose = $false; uninstallVerified = $false
    }
    $expectedIdentity = [ordered]@{
        packageName='Trieflow.CutQuay.Qualification'; publisher='CN=CutQuay-CI-Qualification'; version='1.0.0.0'
        architecture='x64'; applicationId='CutQuay'; executable='CutQuay.exe'
        deviceFamily='Windows.Desktop'; minVersion='10.0.19041.0'; maxVersionTested='10.0.26100.0'; capability='runFullTrust'
    }

    $operations = [ordered]@{}
    $operations.Preflight = {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $env:CI -ne 'true') { throw 'Requires an isolated disposable Windows CI runner.' }
        foreach ($argument in @($PackagePath,$RecordPath,$SignToolPath,$OutputPath)) {
            if (-not $argument) { throw 'Package, package record, SignTool, and output are required.' }
        }
        $state.package = (Resolve-Path -LiteralPath $PackagePath).Path
        $recordFile = (Resolve-Path -LiteralPath $RecordPath).Path
        $state.signTool = (Resolve-Path -LiteralPath $SignToolPath).Path
        if ([IO.Path]::GetFileName($state.signTool) -ine 'signtool.exe') { throw 'Exact SignTool.exe path is required.' }
        $outputCandidate = [IO.Path]::GetFullPath($OutputPath)
        if (Test-Path -LiteralPath $outputCandidate) { throw 'Qualification output already exists and will not be replaced.' }
        New-Item -ItemType Directory -Path $outputCandidate -ErrorAction Stop | Out-Null
        $state.output = $outputCandidate
        $state.record = Get-Content -LiteralPath $recordFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($state.record.schemaVersion -ne 1 -or -not $state.record.qualificationIdentityOnly -or $state.record.signed -or $state.record.publicRelease -or $state.record.licenseClearanceClaimed -or $state.record.installationQualificationPassed) {
            throw 'Package record is not an unsigned qualification-only record.'
        }
        foreach ($field in $expectedIdentity.Keys) {
            if ([string]$state.record.identity.$field -cne [string]$expectedIdentity[$field]) { throw "Qualification identity mismatch: $field" }
        }
        $state.unsignedPackageSha256 = (Get-FileHash -LiteralPath $state.package -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($state.unsignedPackageSha256 -ne ([string]$state.record.containerVerification.package.sha256).ToLowerInvariant()) { throw 'Unsigned package hash differs from verified package record.' }
        $sdkVersion = [regex]::Escape([string]$state.record.makeAppx.sdkVersion)
        if ($state.signTool -notmatch "(?i)[\\/]$sdkVersion[\\/]x64[\\/]signtool\.exe$") { throw 'SignTool does not match the exact qualified Windows SDK x64 directory.' }
        if ([IO.Path]::GetDirectoryName($state.signTool) -ine [IO.Path]::GetDirectoryName([string]$state.record.makeAppx.path)) { throw 'SignTool is not the exact sibling of the qualified MakeAppx tool.' }
        $state.signTool = [ordered]@{
            path = $state.signTool
            bytes = (Get-Item -LiteralPath $state.signTool).Length
            sha256 = (Get-FileHash -LiteralPath $state.signTool -Algorithm SHA256).Hash.ToLowerInvariant()
            sdk_version = [string]$state.record.makeAppx.sdkVersion
        }
        $existing = @(Get-AppxPackage -Name $expectedIdentity.packageName -ErrorAction Stop)
        $state.preflightPackageFullNames = @($existing | ForEach-Object { [string]$_.PackageFullName })
        if ($existing.Count -gt 0) { throw 'A matching CutQuay qualification package is already installed; refusing to replace or remove it.' }
    }.GetNewClosure()

    $operations.PrepareSignedCopy = {
        $runnerTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
        $state.temporary = Join-Path $runnerTemp ('.cutquay-install-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $state.temporary -ErrorAction Stop | Out-Null
        $state.signedCopy = Join-Path $state.temporary 'CutQuay.Qualification.signed.msix'
        [IO.File]::Copy($state.package, $state.signedCopy, $false)
        $state.publicCertificate = Join-Path $state.temporary 'CutQuay.Qualification.public.cer'
        $state.certificate = New-SelfSignedCertificate -Type Custom -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -KeySpec Signature `
            -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}') `
            -Subject $expectedIdentity.publisher -FriendlyName 'CutQuay ephemeral CI qualification' -NotAfter (Get-Date).AddHours(12)
        Export-Certificate -Cert $state.certificate -FilePath $state.publicCertificate -Force | Out-Null
        $state.trustAttempted = $true
        $state.trustedCertificate = Import-Certificate -FilePath $state.publicCertificate -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'
        foreach ($arguments in @(
            @('sign','/fd','SHA256','/sha1',$state.certificate.Thumbprint,'/s','My',$state.signedCopy),
            @('verify','/pa','/all','/v',$state.signedCopy)
        )) {
            if ((Get-Item -LiteralPath $state.signTool.path).Length -ne $state.signTool.bytes -or
                (Get-FileHash -LiteralPath $state.signTool.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $state.signTool.sha256) {
                throw 'SignTool changed after qualification preflight.'
            }
            Invoke-CheckedNative $state.signTool.path $arguments
        }
        if ((Get-Item -LiteralPath $state.signTool.path).Length -ne $state.signTool.bytes -or
            (Get-FileHash -LiteralPath $state.signTool.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $state.signTool.sha256) {
            throw 'SignTool changed during qualification signing.'
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $state.signedCopy
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $signature.SignerCertificate.Thumbprint -ne $state.certificate.Thumbprint) {
            throw "Test-copy signature is not valid for the ephemeral certificate: $($signature.Status)"
        }
        if ((Get-FileHash -LiteralPath $state.package -Algorithm SHA256).Hash.ToLowerInvariant() -ne $state.unsignedPackageSha256) { throw 'Unsigned source package changed during signing.' }
        $state.signedPackageSha256 = (Get-FileHash -LiteralPath $state.signedCopy -Algorithm SHA256).Hash.ToLowerInvariant()
    }.GetNewClosure()

    $operations.Install = {
        $state.activationStarted = [DateTime]::UtcNow
        $state.installAttempted = $true
        Add-AppxPackage -Path $state.signedCopy -ErrorAction Stop
        $state.addCompleted = $true
        $matches = @(Get-AppxPackage -Name $expectedIdentity.packageName -ErrorAction Stop)
        if ($matches.Count -ne 1) { throw 'Expected exactly one installed qualification package.' }
        $candidate = $matches[0]
        if ([string]$candidate.Name -cne $expectedIdentity.packageName -or
            [string]$candidate.Publisher -cne $expectedIdentity.publisher -or
            [string]$candidate.Version -cne $expectedIdentity.version -or
            [string]$candidate.Architecture -cne 'X64' -or
            -not ([string]$candidate.PackageFullName).StartsWith($expectedIdentity.packageName + '_' + $expectedIdentity.version + '_x64_', [StringComparison]::Ordinal) -or
            -not [string]$candidate.PackageFamilyName) {
            throw 'Installed publisher/version/architecture differs from qualification identity.'
        }
        # Ownership is established only after our Add succeeds and one exact
        # expected registration is observed. A failed/partial Add cannot confer it.
        $state.installed = $candidate
        $state.ownedPackageFullName = [string]$candidate.PackageFullName
        $state.installedByUs = $true
        $state.aumid = [string]$state.installed.PackageFamilyName + '!' + $expectedIdentity.applicationId
        foreach ($entry in $state.record.payload.PSObject.Properties) {
            $relative = $entry.Name
            $expected = Get-RecordPayloadEntry $state.record $relative
            $hash = Assert-FileMatchesRecord (Join-Path $state.installed.InstallLocation ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)) $expected $relative
            if ($relative -eq 'CutQuay.exe') { $state.executableSha256 = $hash }

        }
    }.GetNewClosure()

    $operations.VerifyInstalledMedia = {
        $state.media = @(Test-InstalledMedia $state)
    }.GetNewClosure()

    $operations.CaptureInstalledStderr = {
        Add-CutQuayActivationTypes
        $stdoutPath = Join-Path $state.output 'installed-native-stdout.txt'
        $stderrPath = Join-Path $state.output 'installed-native-stderr.txt'
        $executable = Join-Path $state.installed.InstallLocation 'CutQuay.exe'
        $state.process = Start-Process -FilePath $executable -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -ErrorAction Stop
        $null = $state.process.Handle
        $state.ownedProcesses.Add($state.process)
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        do {
            Start-Sleep -Milliseconds 250
            $state.process.Refresh()
            if ($state.process.HasExited) { throw "Installed stderr probe exited during startup: $($state.process.ExitCode)" }
        } until ($state.process.MainWindowHandle -ne 0 -or [DateTime]::UtcNow -ge $deadline)
        if ($state.process.MainWindowHandle -eq 0) { throw 'Installed stderr probe did not create a main window.' }
        $state.diagnosticPackageFullName = [CutQuayQualification.NativePackageProbe]::GetFullName($state.process.Handle)
        if ($state.diagnosticPackageFullName -cne [string]$state.installed.PackageFullName) { throw 'Direct installed stderr probe lacks the exact package identity.' }
        Start-Sleep -Seconds 2
        Update-OwnedPackageProcesses $state
        if (-not $state.process.CloseMainWindow() -or -not $state.process.WaitForExit(15000)) { throw 'Installed stderr probe did not close normally.' }
        if ($state.process.ExitCode -ne 0) { throw "Installed stderr probe exited with $($state.process.ExitCode)." }
        Wait-OwnedPackageExit $state
        $state.diagnosticCleanClose = $true
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding utf8 } else { '' }
        $state.diagnosticStderr = [ordered]@{
            bytes = if (Test-Path -LiteralPath $stderrPath) { (Get-Item -LiteralPath $stderrPath).Length } else { 0 }
            sha256 = if (Test-Path -LiteralPath $stderrPath) { (Get-FileHash -LiteralPath $stderrPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
            fatal_error = ($stderr -match '(?i)unhandled exception|uncaught exception|a javascript error occurred|traceback|fatal error|script error')
        }
        if ($state.diagnosticStderr.fatal_error) { throw 'Installed stderr reports an unhandled/fatal startup failure.' }
    }.GetNewClosure()

    $operations.ActivateAndVerify = {
        Add-CutQuayActivationTypes
        $processId = [CutQuayQualification.ActivationBroker]::Activate($state.aumid)
        $state.brokerProcessId = [int]$processId
        $state.process = [Diagnostics.Process]::GetProcessById([int]$processId)
        $null = $state.process.Handle
        $state.ownedProcesses.Add($state.process)
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        do {
            Start-Sleep -Milliseconds 250
            $state.process.Refresh()
            if ($state.process.HasExited) { throw "Activated CutQuay exited during startup: $($state.process.ExitCode)" }
        } until ($state.process.MainWindowHandle -ne 0 -or [DateTime]::UtcNow -ge $deadline)
        if ($state.process.MainWindowHandle -eq 0) { throw 'Activated CutQuay did not create a main window.' }
        if ($state.record.runtime.application.expectedWindowTitle -cne 'CutQuay') { throw 'Unexpected source title contract.' }
        if ($state.process.MainWindowTitle -cne $state.record.runtime.application.expectedWindowTitle) { throw "Unexpected activated main-window title: $($state.process.MainWindowTitle)" }
        $state.processPackageFullName = [CutQuayQualification.NativePackageProbe]::GetFullName($state.process.Handle)
        if ($state.processPackageFullName -cne [string]$state.installed.PackageFullName) { throw 'Activated process does not own the exact installed package full name.' }
        if ((Get-CanonicalPath $state.process.MainModule.FileName) -ine (Get-CanonicalPath (Join-Path $state.installed.InstallLocation 'CutQuay.exe'))) { throw 'Broker returned an executable outside the exact installed main path.' }
        Update-OwnedPackageProcesses $state
        $installRoot = Get-CanonicalPath $state.installed.InstallLocation
        $windowsRoot = Get-CanonicalPath $env:SystemRoot
        $modules = [Collections.Generic.List[object]]::new()
        $mainExecutableLoaded = $false
        foreach ($ownedProcess in @($state.ownedProcesses)) {
            if ($ownedProcess.HasExited) { continue }
            foreach ($module in @($ownedProcess.Modules)) {
                $path = Get-CanonicalPath $module.FileName
                if (Test-PathInside $path $installRoot) {
                    $relative = $path.Substring($installRoot.Length).TrimStart('\','/').Replace('\','/')
                    $expected = Get-RecordPayloadEntry $state.record $relative
                    $hash = Assert-FileMatchesRecord $path $expected "Loaded module $relative"
                    if ($relative -ceq 'CutQuay.exe') { $mainExecutableLoaded = $true }
                    $origin = 'package'
                } elseif (Test-PathInside $path $windowsRoot) {
                    $relative = $null
                    $hash = $null
                    $origin = 'windows'
                } else {
                    throw "Activated package loaded a module outside its package and Windows: $path"
                }
                $modules.Add([ordered]@{ process_id=$ownedProcess.Id; name=$module.ModuleName; path=$path; origin=$origin; relative_path=$relative; sha256=$hash })
            }
        }
        if (-not $mainExecutableLoaded) { throw 'Activated process did not load the exact installed CutQuay.exe.' }
        $state.modules = @($modules)
        Write-NewUtf8Json (Join-Path $state.output 'loaded-modules.json') $state.modules
        $state.window = Get-WindowQualification $state.process $state.output
        $state.window['title'] = $state.process.MainWindowTitle
        if (-not $state.window.screenshot_captured) { throw ('Required startup screenshot failed: ' + $state.window.screenshot_error) }
        Start-Sleep -Seconds 3
        $state.process.Refresh()
        if ($state.process.HasExited -or $state.process.MainWindowHandle -eq 0) { throw 'Activated CutQuay did not survive the stable-window interval.' }
    }.GetNewClosure()

    $operations.CloseCleanly = {
        Update-OwnedPackageProcesses $state
        if (-not $state.process.CloseMainWindow()) { throw 'Activated CutQuay refused a normal main-window close request.' }
        if (-not $state.process.WaitForExit(15000)) { throw 'Activated CutQuay did not exit after a normal close request.' }
        if ($state.process.ExitCode -ne 0) { throw "Activated CutQuay exited with $($state.process.ExitCode) after normal close." }
        Wait-OwnedPackageExit $state
        $state.cleanClose = $true
    }.GetNewClosure()

    $operations.UninstallAndVerify = {
        if (-not $state.installedByUs -or -not $state.ownedPackageFullName) { throw 'Exact installed package ownership was not established.' }
        Remove-AppxPackage -Package $state.ownedPackageFullName -ErrorAction Stop
        if (@(Get-AppxPackage -Name $expectedIdentity.packageName -ErrorAction Stop).Count -ne 0) { throw 'Package registration remains after uninstall.' }
        $state.uninstallVerified = $true
    }.GetNewClosure()

    $operations.StopOwnedProcess = {
        $errors = [Collections.Generic.List[string]]::new()
        if ($state.installed) {
            try { Update-OwnedPackageProcesses $state } catch { $errors.Add($_.Exception.Message) }
        }
        if ($state.mediaProcess -and -not $state.mediaProcess.HasExited) {
            try { $state.mediaProcess.Kill($true); if (-not $state.mediaProcess.WaitForExit(10000)) { throw 'Owned media probe did not stop.' } }
            catch { $errors.Add($_.Exception.Message) }
        }
        foreach ($owned in @($state.ownedProcesses)) {
            try {
                if (-not $owned.HasExited) {
                    $owned.Kill()
                    if (-not $owned.WaitForExit(10000)) { throw 'Owned Electron process did not stop.' }
                }
            } catch { $errors.Add($_.Exception.Message) }
        }
        if ($errors.Count) { throw ($errors -join '; ') }
    }.GetNewClosure()

    $operations.RemoveOwnedPackage = {
        if ($state.installAttempted) {
            $remaining = @(Get-AppxPackage -Name $expectedIdentity.packageName -ErrorAction Stop)
            $state.residualPackageFullNames = @($remaining | ForEach-Object { [string]$_.PackageFullName })
            if ($state.installedByUs -and $state.ownedPackageFullName) {
                $owned = @($remaining | Where-Object { [string]$_.PackageFullName -ceq $state.ownedPackageFullName })
                if ($owned.Count -gt 1) { throw 'Ambiguous duplicate registration state; all registrations preserved.' }
                if ($owned.Count -eq 1) { Remove-AppxPackage -Package $state.ownedPackageFullName -ErrorAction Stop }
            }
            # A matching registration after a failed Add may belong to another
            # invocation. Report residue without removing identity-tuple matches.
            $remaining = @(Get-AppxPackage -Name $expectedIdentity.packageName -ErrorAction Stop)
            $state.residualPackageFullNames = @($remaining | ForEach-Object { [string]$_.PackageFullName })
            if ($remaining.Count) { throw ('Unowned or unresolved package registrations preserved: ' + ($state.residualPackageFullNames -join ', ')) }
        }
    }.GetNewClosure()

    $operations.RemoveTrustedCertificate = {
        if ($state.trustAttempted -and $state.certificate) {
            $path = 'Cert:\LocalMachine\TrustedPeople\' + $state.certificate.Thumbprint
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $path) { throw 'Trusted public certificate remains after cleanup.' }
        }
    }.GetNewClosure()

    $operations.RemovePersonalCertificate = {
        if ($state.certificate) {
            $path = 'Cert:\CurrentUser\My\' + $state.certificate.Thumbprint
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
            if (Test-Path -LiteralPath $path) { throw 'Ephemeral personal certificate remains after cleanup.' }
        }
    }.GetNewClosure()

    $operations.RemoveTemporaryFiles = {
        if ($state.temporary -and (Test-Path -LiteralPath $state.temporary)) {
            Remove-Item -LiteralPath $state.temporary -Recurse -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $state.temporary) { throw 'Temporary signed-copy directory remains after cleanup.' }
        }
    }.GetNewClosure()

    $result = Invoke-CutQuayQualificationCore -Operations $operations
    if (-not $state.output) {
        # An output collision is intentionally not overwritten and cannot receive evidence.
        throw "Qualification failed before evidence directory ownership. Primary: $($result.primary_error); cleanup: $($result.cleanup_errors -join '; ')"
    }
    $evidenceErrors = [Collections.Generic.List[string]]::new()
    $unsignedUnchanged = $false
    if ($state.unsignedPackageSha256 -and $state.package) {
        try {
            $unsignedUnchanged = (Get-FileHash -LiteralPath $state.package -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -eq $state.unsignedPackageSha256
            if (-not $unsignedUnchanged) { $evidenceErrors.Add('Unsigned package changed after qualification.') }
        } catch {
            $evidenceErrors.Add('Unsigned package final verification failed: ' + $_.Exception.Message)
        }
    } elseif ($result.installation_qualification_passed) {
        $evidenceErrors.Add('Successful core qualification did not retain the unsigned package identity.')
    }
    $qualificationPassed = $result.installation_qualification_passed -and $unsignedUnchanged -and $evidenceErrors.Count -eq 0
    $evidence = [ordered]@{
        schema_version = 1
        generated_at_utc = [DateTime]::UtcNow.ToString('o')
        source_commit = if ($state.record) { [string]$state.record.sourceCommit } else { $null }
        qualification_identity_only = $true
        identity = $expectedIdentity
        aumid = $state.aumid
        package_full_name = if ($state.installed) { [string]$state.installed.PackageFullName } else { $null }
        add_appx_completed = $state.addCompleted
        registration_ownership_established = $state.installedByUs
        owned_package_full_name = $state.ownedPackageFullName
        preflight_package_full_names = @($state.preflightPackageFullNames)
        residual_package_full_names = @($state.residualPackageFullNames)
        activated_process_package_full_name = $state.processPackageFullName
        diagnostic_process_package_full_name = $state.diagnosticPackageFullName
        diagnostic_stderr = $state.diagnosticStderr
        diagnostic_clean_close_verified = $state.diagnosticCleanClose
        unsigned_package_sha256 = $state.unsignedPackageSha256
        signed_copy_sha256 = $state.signedPackageSha256
        unsigned_package_unchanged = $unsignedUnchanged
        signtool = $state.signTool
        certificate_private_key_exported = $false
        executable_sha256 = $state.executableSha256
        installed_media = $state.media
        electron_version = if ($state.record) { $state.record.runtime.electron.version } else { $null }
        loaded_module_count = @($state.modules).Count
        window = $state.window
        clean_close_verified = $state.cleanClose
        uninstall_verified = $state.uninstallVerified
        installation_qualification_passed = $qualificationPassed
        workflow_acceptance = $false
        export_workflow_tested = $false
        upgrade_tested = $false
        wack_tested = $false
        store_identity_used = $false
        public_release = $false
        primary_error = $result.primary_error
        cleanup_errors = @($result.cleanup_errors)
        evidence_errors = @($evidenceErrors)
    }
    try {
        Write-NewUtf8Json (Join-Path $state.output 'installation-qualification.json') $evidence
    } catch {
        throw "Could not preserve qualification JSON: $($_.Exception.Message). Primary: $($result.primary_error); cleanup: $($result.cleanup_errors -join '; '); evidence: $($evidenceErrors -join '; ')"
    }
    if (-not $qualificationPassed) {
        throw "CutQuay installation qualification failed. Primary: $($result.primary_error); cleanup: $($result.cleanup_errors -join '; '); evidence: $($evidenceErrors -join '; ')"
    }
    Write-Output 'PASS: broker-activated exact package, verified owned modules/window/close, uninstalled, and cleaned certificate state.'
}

if (-not $LibraryOnly) {
    try {
        Invoke-CutQuayInstallQualification -PackagePath $Package -RecordPath $PackageRecord -SignToolPath $SignTool -OutputPath $Output
    } catch {
        Write-Error $_
        exit 1
    }
}
