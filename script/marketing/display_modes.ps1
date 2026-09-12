# Copyright 2026 Trieflow LLC. MIT. Native desktop modes; no emulation or registry writes.
function Add-MarketingDisplayTypes {
    if('CutQuayMarketing.DisplayModes' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace CutQuayMarketing {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
 public struct DisplayDevice {
  public int cb;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string DeviceName;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceString;
  public uint StateFlags;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceID;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceKey;
 }
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
 public struct Mode {
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmDeviceName;
  public ushort dmSpecVersion,dmDriverVersion,dmSize,dmDriverExtra;
  public uint dmFields;
  public int dmPositionX,dmPositionY;
  public uint dmDisplayOrientation,dmDisplayFixedOutput;
  public short dmColor,dmDuplex,dmYResolution,dmTTOption,dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmFormName;
  public ushort dmLogPixels;
  public uint dmBitsPerPel,dmPelsWidth,dmPelsHeight,dmDisplayFlags,dmDisplayFrequency;
  public uint dmICMMethod,dmICMIntent,dmMediaType,dmDitherType,dmReserved1,dmReserved2,dmPanningWidth,dmPanningHeight;
 }
 public static class DisplayModes {
  [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool EnumDisplayDevicesW(string device,uint index,ref DisplayDevice value,uint flags);
  [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool EnumDisplaySettingsW(string device,int index,ref Mode value);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsExW(string device,ref Mode value,IntPtr hwnd,uint flags,IntPtr parameter);
  static Mode NewMode(){if(Marshal.SizeOf<Mode>()!=220)throw new InvalidOperationException("DEVMODEW layout differs");return new Mode{dmSize=220};}
  public static string Primary(){
   var names=new List<string>();
   for(uint i=0;i<16;i++){var device=new DisplayDevice{cb=Marshal.SizeOf<DisplayDevice>()};if(!EnumDisplayDevicesW(null,i,ref device,0))break;if((device.StateFlags&5)==5)names.Add(device.DeviceName);}
   if(names.Count!=1)throw new InvalidOperationException("Exactly one attached primary display is required");return names[0];
  }
  public static Mode Current(string device){var mode=NewMode();if(!EnumDisplaySettingsW(device,-1,ref mode))throw new Win32Exception(Marshal.GetLastWin32Error());if(mode.dmDriverExtra!=0)throw new InvalidOperationException("Private display-driver mode data is unsupported");return mode;}
  public static Mode[] Supported(string device){
   var modes=new List<Mode>();
   for(int i=0;i<=256;i++){var mode=NewMode();if(!EnumDisplaySettingsW(device,i,ref mode))return modes.ToArray();if(i==256)throw new InvalidOperationException("Display inventory exceeds bound");if(mode.dmDriverExtra!=0)throw new InvalidOperationException("Private display-driver mode data is unsupported");modes.Add(mode);}
   throw new InvalidOperationException("Unreachable display inventory state");
  }
  public static int Change(string device,Mode mode,uint flags){if(flags!=0&&flags!=2)throw new InvalidOperationException("Only native test and dynamic change are allowed");return ChangeDisplaySettingsExW(device,ref mode,IntPtr.Zero,flags,IntPtr.Zero);}
 }
}
'@
}

function Convert-MarketingMode($Mode){
    return [ordered]@{width=$Mode.dmPelsWidth;height=$Mode.dmPelsHeight;bits=$Mode.dmBitsPerPel;frequency=$Mode.dmDisplayFrequency;orientation=$Mode.dmDisplayOrientation;flags=$Mode.dmDisplayFlags}
}

function Get-MarketingModeChoice($Modes){
    $candidates=@($Modes|Where-Object {$_.dmBitsPerPel -eq 32 -and $_.dmPelsWidth -ge 1472 -and $_.dmPelsHeight -ge 1080 -and
        $_.dmPelsWidth -le 2560 -and $_.dmPelsHeight -le 1440 -and $_.dmDisplayOrientation -eq 0 -and ($_.dmDisplayFlags -band 2) -eq 0 -and $_.dmDriverExtra -eq 0}|
        Sort-Object @{Expression={[Math]::Abs([int]$_.dmPelsWidth-1920)+[Math]::Abs([int]$_.dmPelsHeight-1080)}},@{Expression={[Math]::Abs([int]$_.dmDisplayFrequency-60)}})
    if(-not $candidates.Count){throw 'No adequate enumerated 32-bpp native display mode exists; capture remains incomplete.'}
    return $candidates[0]
}

function Get-MarketingDisplayState([string]$Device){
    Add-MarketingDisplayTypes
    if(-not $Device){$Device=[CutQuayMarketing.DisplayModes]::Primary()}
    return @{device=$Device;current=[CutQuayMarketing.DisplayModes]::Current($Device);modes=[CutQuayMarketing.DisplayModes]::Supported($Device)}
}
function Set-MarketingDisplayMode([string]$Device,$Mode,[int]$Flags){
    return [CutQuayMarketing.DisplayModes]::Change($Device,$Mode,$Flags)
}

function Start-MarketingDisplay($State){
    $snapshot=Get-MarketingDisplayState
    $State.displayOriginalMode=$snapshot.current;$State.displayDevice=$snapshot.device
    $State.displayEvidence=[ordered]@{purpose='actual native display only';device=$snapshot.device;before=(Convert-MarketingMode $snapshot.current);
        supported_modes=@($snapshot.modes|ForEach-Object {Convert-MarketingMode $_});selected=$null;test_result=$null;apply_result=$null;after=$null;
        registry_updated=$false;unsafe_modes_enabled=$false;dpi_changed=$false;renderer_emulation_used=$false;restore_result=$null;restored=$null;restore_verified=$false}
    if($snapshot.current.dmPelsWidth -ge 1472 -and $snapshot.current.dmPelsHeight -ge 1080 -and $snapshot.current.dmBitsPerPel -eq 32){
        $State.displayEvidence.after=Convert-MarketingMode $snapshot.current;return
    }
    $selected=Get-MarketingModeChoice $snapshot.modes;$State.displayEvidence.selected=Convert-MarketingMode $selected
    $test=Set-MarketingDisplayMode $snapshot.device $selected 2;$State.displayEvidence.test_result=$test
    if($test -ne 0){throw "Native display CDS_TEST failed ($test); no mode was applied."}
    # Set before the native call so any partial failure still restores the
    # retained original DEVMODE on this exact display device.
    $State.displayRestoreRequired=$true
    $apply=Set-MarketingDisplayMode $snapshot.device $selected 0;$State.displayEvidence.apply_result=$apply
    if($apply -ne 0){throw "Native dynamic display change failed ($apply)."}
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do{
        $after=(Get-MarketingDisplayState $snapshot.device).current
        if($after.dmPelsWidth -eq $selected.dmPelsWidth -and $after.dmPelsHeight -eq $selected.dmPelsHeight -and $after.dmBitsPerPel -eq 32){break}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    $State.displayEvidence.after=Convert-MarketingMode $after
    if($after.dmPelsWidth -ne $selected.dmPelsWidth -or $after.dmPelsHeight -ne $selected.dmPelsHeight -or $after.dmBitsPerPel -ne 32){throw 'Native display change did not take effect.'}
}

function Restore-MarketingDisplay($State){
    if(-not $State.displayOriginalMode){return}
    if($State.displayRestoreRequired){
        $result=Set-MarketingDisplayMode $State.displayDevice $State.displayOriginalMode 0;$State.displayEvidence.restore_result=$result
        if($result -ne 0){throw "Native display restoration failed ($result)."}
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do{
        $observed=Convert-MarketingMode (Get-MarketingDisplayState $State.displayDevice).current
        $same=($observed|ConvertTo-Json -Compress) -ceq ($State.displayEvidence.before|ConvertTo-Json -Compress)
        if($same){break};Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    $State.displayEvidence.restored=$observed;$State.displayEvidence.restore_verified=$same
    if(-not $same){throw 'Retained original native display mode was not restored.'}
}
