
write-host Initializing...

# the default is to write error and continue execution.
$ErrorActionPreference = "Stop"
set-strictmode -Version Latest

$env:DEFAULT_TEXT_EDITOR = "C:\Program Files\Sublime Text 2\sublime_text.exe";

# sequence helpers.
$seq = [System.Linq.Enumerable]

### fixup module path ###
$modulePath = "C:\Program Files (x86)\PowerShell Community Extensions\Pscx3\;"
if (-not $env:PSModulePath.Contains($modulePath)) {
    $env:PSModulePath = $modulePath + $env:PSModulePath
}

$env:Path += ";c:\dev\tools;c:\dbg32;C:\Program Files (x86)\Windows Installer XML v3.5\bin;";

#### import powershell community extensions ####
Import-Module Pscx

function bye {
  shutdown -s -t 0 -f
}

function append ([string] $line, $file) {
  # TODO: okay actually this should open the file, detect encoding, then appendline.
  Write-Output $line | out-file -Append -Encoding utf8 $file
}

function Hex-ToAscii( [string]$value ) {
    $value.Split('-') | 
        % { write-host -NoNewLine ([char]([Convert]::ToInt32($_, 16))) }
    
    write-host "`r`n"
}

function new-guid {
    [guid]::NewGuid();
}

########### PERFORMANCE PROFILING #######
function get-assemblies([string] $path, [regex] $expr) {
    # if you havin' regex problems I feel bad for you son
    # I got \d+ problems and matching text ain't one.
    dir $path | where { $expr.IsMatch($_.Name) } | select Name
}
 
function instrument-binaries ([string] $basePath, $assemblies) {
    $profilerPath = "C:\Program Files (x86)\Microsoft Visual Studio 10.0\Team Tools\Performance Tools"
 
    if (-not ($env:Path.Contains($profilerPath))) {
        write-host "appending vs_profiler path to Path environment variable."
        $env:Path += (";" + $profilerPath);
    }
 
    push-location $basePath
 
    if (-not (test-path ( where.exe VsInstr.exe ))) {
        write-host "VsInstr.exe is not installed!"
    } else {
        $flag = "is a delay-signed or test-signed assembly"
 
        foreach ($instr in $assemblies) {
            $path = [System.IO.Path]::Combine($basePath, $instr);
 
            VsInstr.exe $path /ExcludeSmallFuncs
 
            $output = (sn.exe -v $path)
            $resign = (($output -match $flag).Count -gt 0)
                 
            if ($resign) {
                write-host $instr needs to be resigned...
                # assuming your keyfile is in the project root.
                # adjust accordingly
                sn.exe -Ra "$path" ..\..\your-keyfile-here.snk
            }
        }
    }
 
    pop-location
}

function begin-profiling ( [string] $session, [string] $report_path ) {
    if (-not (test-path $report_path )) {
        mkdir "$report_path"| out-null
    }
 
    $env:_NT_SYMBOL_PATH = "srv*C:\mssymbols*http://msdl.microsoft.com/downloads/symbols"
    $profilerPath = "C:\Program Files (x86)\Microsoft Visual Studio 10.0\Team Tools\Performance Tools"
 
    if (-not ($env:Path.Contains($profilerPath))) {
        $env:Path += (";" + $profilerPath);
    }
 
    # make sure the profiler isn't already running.
    VsPerfCmd.exe /Status
 
    if ($LastExitCode -ne 0) {
        $name = $session + [DateTime]::Now.ToString("MM-dd-yyyy-hh-mm")
        $report = $report_path + $name + ".vsp"
 
        VsPerfCmd.exe /user:Everyone /start:Trace /output:$report /CrossSession
 
        write-host "Profiling report will be stored in:" $report
    } else {
        write-host "Profiler already running. New session will not be started."
    }
}

function end-profiling {
    VsPerfCmd.exe /GlobalOff
    VsPerfCmd /Shutdown
    VsPerfClrEnv /off
 
    write-host "Profilers detached."
}

#############################################################################################################
############################################### BUILD HELPERS ###############################################
#############################################################################################################

<#
    .SYNOPSIS 
        build helper with some default settings for my most common build args.

    .DESCRIPTION 
        rebuilds the specified solution passing the given arguments

    .PARAMETER solution 
        the path to the solution file

    .PARAMETER config 
        the build configuration

    .PARAMETER referencePaths 
        paths to include when building the solution.
#>
function build-solution ([string]$solution, [string]$config="Release", [string[]]$referencePaths = $null) {
    $start = get-date
    $targets = " /t:Build "
    $params = " /p:Configuration=$config "

    if ($referencePaths) {
        foreach ($path in $referencePaths) {
            $resolved = resolve-path $path
            $params += " /p:ReferencePath=$resolved " 
        }
    }

    $cmd = "msbuild $solution $targets $params /m /clp:Verbosity=minimal /flp:Summary /flp:Verbosity=detailed /nologo /nr:true /clp:Summary"
    
    write-host "invoking: $cmd"

    iex $cmd

    $elapsed = (get-date) - $start
    write-host "Elapsed time: $elapsed"
}

function clean-solution ([string]$solution, [string]$config="Release") {
    & msbuild $solution /t:Clean /p:Configuration=$config /m /v:d /nologo
}

<# loads up some xml instead of using the [xml] helpers which read line-by-line. #>
function load-xml () {
    Param([Parameter(Mandatory = $true)] [string]$relativePath)
        
    $path = resolve-path $relativePath
    [xml] $root = new-object xml

    $root.load($path);

    return $root;
}

<# #>
function search-configs($search) {
    (dir . -filter *.config -Recurse) | 
        % { 
            $matches = gc $_.FullName | select-string -Pattern $search;

            if ($matches) {
                $obj = new-object PSObject;
                $obj | add-member Noteproperty File $_.FullName;
                $obj | add-member Noteproperty Matches $matches;

                $obj
            }
        } | format-list *
}

<#
    .SYNOPSIS
        Helpful cmdlet for recycling app pools.

    .DESCRIPTION 
        Recycles an app pool, either on the local machine or on a remote server through PSExec (requires SysInternals tools)

        When recycling on a remote system, the command will display an error if psexec.exe is not found on the system path.

    .PARAMETER poolName
        Specifies the name of the pool to recycle.

    .PARAMETER server
        Indicates that the app pool to recycle resides on another server.

    .PARAMETER iis6
        Indicates that this server is running IIS6. (default = false)
#>
function recycle-apppool {
    Param(
        [Parameter(Mandatory = $true)] [string]$poolName, 
        [Parameter(Mandatory = $false)] [string]$server, 
        [Parameter(Mandatory = $false)] [switch]$iis6
    )

    $cmd = "c:\windows\system32\inetsrv\appcmd.exe recycle apppool /apppool.name:$poolName";
    
    if ($iis6) {
        $cmd = "cscript.exe iisapp.vbs /a $poolName /r"
    }

    if ($server) {

        $path = (where.exe psexec.exe)

        if (-not $path) {
            write-error "PSExec.exe not found on the path. This is required to use this function."
            return;
        }

        $cmd = "psexec.exe \\$server " + $cmd;
    }

    Invoke-Expression $cmd;
}

<#
    .SYNOPSIS
        Helpful cmdlet for listing app pools.

    .DESCRIPTION 
        Lists all AppPools, either on the local machine or on a remote server through PSExec (requires SysInternals tools)

        When listing app pools on a remote system, the command will display an error if psexec.exe is not found on the system path.

    .PARAMETER server
        Specifies the remote server to connect to (default = $env:ComputerName)

    .PARAMETER iis6
        Indicates that this server is running IIS6. (default = false)
#>
function list-apppool {
    Param(
        [Parameter(Mandatory = $false)] [string]$server, 
        [Parameter(Mandatory = $false)] [switch]$iis6
    )

    if ($iis6) {
        if (-not $server) {
            $server = $env:ComputerName;
        }

        $map = @{ 
            1 = "starting"; 
            2 = "started"; 
            3 = "stopping"; 
            4 = "stopped"
        };

        $pools = [ADSI]"IIS://$server/W3SVC/AppPools";
        $pools | 
            % { $_.children } | 
                select Name, @{Name="State";Expression={$map[$_.AppPoolState.Value]}}

    } else {
        $cmd = "c:\windows\system32\inetsrv\appcmd.exe list apppool";
        
        if ($server) {
            $path = (where.exe psexec.exe)
            if (-not $path) {
                write-error "PSExec.exe not found on the path. This is required to use this function."
                return;
            }
            $cmd = "psexec.exe \\$server " + $cmd;
        }

        Invoke-Expression $cmd
    }
}

function display-date ([datetime] $date) {
    $format = "MM/dd/yyyy HH:mm:ss"

    if ($date -ne [DateTime]::MinValue) {
        return $date.ToString($format)
    }
    
    return ""
}

function wget-async ([string] $url) { 
    $client = new-object Net.WebClient; 
    $client.Proxy = $null;

    $name = [system.io.path]::GetFileName($url); 
    $path = [system.io.path]::combine($pwd.Path, $name)

    try {
        $complete = [guid]::newguid();

        Register-ObjectEvent $client DownloadProgressChanged -action {
            $status = "{0} of {1}" -f $eventargs.BytesReceived, $eventargs.TotalBytesToReceive;

            Write-Progress -Activity "Downloading" -Status $status -PercentComplete $eventargs.ProgressPercentage;
        } | out-null

        Register-ObjectEvent $client DownloadFileCompleted -SourceIdentifier $complete | out-null

        $client.DownloadFileAsync($url, $path)
        Wait-Event -SourceIdentifier $complete | out-null
    } finally { 
        $client.dispose();
    }
}

function format-color([hashtable] $colors) {
    $lines = ($input | Out-String) -replace "`r", "" -split "`n"
    foreach ($line in $lines) {
        $color = ''
        foreach ($pattern in $colors.Keys) {
            if ($line -match $pattern) { 
                $color = $colors[$pattern] 
            }
        }

        if ($color) {
            Write-Host -ForegroundColor $color $line
        } else {
            Write-Host $line
        }
    }
}


function list-directory {
  # okay, technically this only makes sense in the context of a FILE
  if ((get-location).Provider.Name.EndsWith("FileSystem")) {
    
    $dir = [system.io.fileattributes]::Directory
    $hidden = [system.io.fileattributes]::Hidden
    $argv = [string]::Join(" ", $args)

    Invoke-Expression "Get-ChildItem $argv -Force" | % {
      $c = "white"
      
      if ($_.Attributes -band $hidden) {
        $c = "darkgray"
      }
      elseif ($_.Attributes -band $dir) {
        $c = "blue"
      } else {
        $extensions = $env:PATHEXT.toLower().split(';')
        if ($extensions -contains $_.extension) {
          $c = "green"
        }
      }

      $ts = $_.LastWriteTime.ToString("MMM dd yyyy")
      $line = $_.Mode + " "+ $(__size($_)) + " " + $ts + " "
      # note: using ansi colors feels sluggish and
      # it doesn't actually make piping to "more" cleaner.
      write-host -NoNewLine $line

      # TODO: if we are recursing, add the path.
      write-host -F $c $_.Name
    }
  } 
  else {
    gci
  }
}

<# helper for ll to display human readable sizes #>
function __size ($f) {
  $dir = [system.io.fileattributes]::Directory
  if ($f.attributes -band $dir) { return "   dir" }

  switch ($f.length) {
    { $_ -gt 1tb } { return "{0,4:n1} T" -f ($_ / 1tb) }
    { $_ -gt 1gb } { return "{0,4:n1} G" -f ($_ / 1gb) }
    { $_ -gt 1mb } { return "{0,4:n1} M" -f ($_ / 1mb) }
    { $_ -gt 1kb } { return "{0,4:n1} K" -f ($_ / 1Kb) }
    default { return "  {0,4:0}" -f $_ } 
  }
}

<# recursive delete, now with pipeline powers#>
function rmrf {
  [cmdletbinding()]
  param(
    [parameter(ValueFromPipeline)]
    [string[]]$stdin
  )

  process {
    foreach ($item in $stdin) {
      Remove-Item $item -Recurse -Force -ErrorAction Ignore
    }
  }
}

function file ($f) {
  (gp $f) | select *
}

##################   ALIASES   ####################
set-alias build build-solution
set-alias recycle recycle-apppool
set-alias lsapp list-apppool

set-alias ll list-directory -Option AllScope
set-alias ls list-directory -Option AllScope

set-alias csc "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
set-alias ngen "C:\Windows\Microsoft.NET\Framework\v4.0.30319\ngen.exe"
set-alias edit "C:\Program Files\Sublime Text 2\sublime_text.exe"
set-alias msbuild "C:\Windows\Microsoft.Net\Framework\v4.0.30319\MSBuild.exe"
set-alias vstest "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe"
