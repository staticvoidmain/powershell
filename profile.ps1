
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
$env:SVN_SERVER = "TODO"

#### import powershell community extensions ####
Import-Module Pscx

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


############ SVN FUNCTIONS ##############
function cleanup-svn {
    $status = svn.exe status --no-ignore

    if (-not($status) -or $status.Length -eq 0) {
        write-host "Working Copy Is Clean!"
    } else {
        write-host "Found local modifications."
        $status | write-host

        $flag = read-host "Are you sure you want to continue?"

        if ($flag -eq "y") {
            write-host "Reverting local modifications..."
            svn.exe revert . -R
        
            write-host "Removing ignored files..."
            $status -match '^[?I].*$' -replace '^.{8}' | 
                % { write-host "Deleting " $_; rm -Path $_ -Recurse -Force }

            write-host "Done!"
        }
    }
}

function update-svn {
    svn.exe update
}

function get-revstats ([int] $revision) {
    [string] $basePath =  "svn://" + $env:SVN_SERVER + "/"
    $fileRegex = [regex] "^Index: (?<file>.*)$"
    $addedLineRegex = [regex] "^\+(?!\+\+).*$"
    $removedLineRegex = [regex] "^\-(?!\-\-).*$"
    $lines = (svn diff $basePath -c $revision)

    $stats = @{};

    [string] $currentFile = "";

    $lines | 
        % {
            $m = $fileRegex.Match($_);

            if ($m.Success) {
                $currentFile = $m.Groups["file"].Value;
                $stats[$currentFile] = [pscustomobject] @{ 
                    Name=$currentFile; 
                    Added=0; 
                    Removed=0 
                };
            } else {
                if ($_.StartsWith("+") -or $_.StartsWith("-")) {
                    if ($addedLineRegex.IsMatch($_)) {
                        $stats[$currentFile].Added++;
                    } elseif ($removedLineRegex.IsMatch($_)) {
                        $stats[$currentFile].Removed++;
                    }
                }
            }
        }

    write-host "(" -NoNewLine
    write-host " Files=$($stats.Count)," -NoNewLine
    write-host " Added=$($seq::sum([int[]]$stats.Values.Added))," -NoNewLine
    write-host " Removed=$($seq::sum([int[]]$stats.Values.Removed))" -NoNewLine
    write-host ")"

    $stats.Values | sort-object -Descending File
}

<#
.SYNOPSIS
    Gets the svn changes associated with a given revision.

.PARAMETER revision
    Specifies the revision to get changes for.

.PARAMETER sequential
    Specifies whether to WAIT for a keypress before opening the next window ( default = true ).

.DESCRIPTION
    The get-svnchanges function pulls the logs for a specific revision and iterates through the changes, 
    opening each file in tortoisemerge to show file differences. If -sequential is specified, then each
    instance of TortoiseMerge.exe is executed in a serial fashion, only on keypress.
#>
function get-svnchanges ([int] $revision, [bool] $sequential = $true) {
    [string] $basePath =  "svn://" + $env:SVN_SERVER + "/"
    [xml] $details = (svn log $basePath/Drive -c $revision --verbose --xml)
    
    $entry = $details.log.logentry

    [int] $revision = $entry.revision;
    [int] $prev = $revision - 1;

    foreach ($file in $entry.paths.path) {
        
        [string] $path = $basePath + $file.innertext;
        [string] $fileName = [System.IO.Path]::GetFileName($file.innertext);

        $current = [System.IO.Path]::GetTempFileName();

        svn.exe cat $path@$revision > $current

        if ($file.action -eq "M") {
            $base = [System.IO.Path]::GetTempFileName();
            svn.exe cat $path@$prev > $base;

            $arguments = "/base:$base", "/mine:$current", "/basename:$($fileName).base", "/minename:$($fileName).current";
            $process = start-process tortoisemerge.exe -PassThru -ArgumentList $arguments;
        } else {
            # if this file was added, previous will be empty and throw an error in diff
            write-host "File added: $path"
            write-host "Opening in text editor."

            $process = start-process $env:DEFAULT_TEXT_EDITOR ".\tmp\current.$fileName";
        }

        if ($sequential) {
            read-host "press any key to continue..."
        }
    }
}

function svn-log {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)] [string] $startDate = (get-date), 
        [Parameter(Mandatory = $false)] [string] $endDate,
        [Parameter(Mandatory = $false)] [string] $path,
        [Parameter(Mandatory = $false)] [string] $user
    )

    [datetime] $startDateParsed = [DateTime]::Parse($startDate);
    [datetime] $endDateParsed = [DateTime]::MinValue;

    if (-not $endDate) {
        $endDateParsed = $startDateParsed.AddDays(1);
    } else {
        $endDateParsed = [DateTime]::Parse($endDate);
    }

    [string] $svnDateFormat = "yyyy-MM-dd";
    [string] $start = $startDateParsed.ToString($svnDateFormat);
    [string] $end = $endDateParsed.ToString($svnDateFormat);

    write-host "fetching svn log for $start - $end"

    [string] $path = "svn://" + $env:SVN_SERVER + "/Drive" + $path
    [string] $rev = "`{" + $start + "`}:`{" + $end + "`}"
    [string[]] $arguments = "log", $path, "--revision", $rev, "--xml", "--verbose"

    $doc = [xml] (svn.exe $arguments)

    $logs = $doc.log.logentry;
    if ($user) {
        write-host "filtering for $user"
        $logs = $doc.log.logentry | where { $_.author -eq $user }
    }

    $logs
}

############## MISC ################
function Hex-ToAscii( [string]$value ) {
    $value.Split('-') | 
        % { write-host -NoNewLine ([char]([Convert]::ToInt32($_, 16))) }
    
    write-host "`r`n"
}

function new-guid {
    [guid]::NewGuid();
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

function run-tests {
    vstest /?
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

<#
    .SYNOPSIS parses an msbuild file looking for errors.
    .DESCRIPTION helps identify build errors without forcing someone to open a large buildlog file.
    .PARAMETER file the .log file to check for errors.
#>
function build-errors {
    Param([Parameter(Mandatory = $true)] [string]$file)
    
    $settings = new-object System.Xml.XmlReaderSettings -Property @{ 
        IgnoreComments=$true; 
        IgnoreWhitespace=$true;
        CloseInput=$true;
    };

    $path = resolve-path $file

    $stream = [System.IO.File]::OpenRead($path);
    $reader = [System.Xml.XmlReader]::Create($stream, $settings);

    $element = [System.Xml.XmlNodeType]::Element

    while ($reader.Read()) {
        if ($reader.NodeType -eq $element) {
            if ($reader.Name -eq "Error") {
                write-host $reader.ReadOuterXml();
            }
        }
    }
}

function build-stats ($buildLog) {
    $root = load-xml $buildLog
    $build = $root.cruisecontrol.build;

    [datetime] $start =  $build.date;
    [datetime] $msbuildStart = $build.msbuild.startTime;

    $times = @();

    $times += new-object PSObject -Property @{ Name="Total"; Elapsed=$($build.buildTime) }
    $times += new-object PSObject -Property @{ Name="[Exec] svn update"; Elapsed=$($msbuildStart.Subtract($start)) }

    $buildProjects = select-xml $build.msbuild -XPath "//project[@name='Build']"

    $buildProjects.Node |
        % { 
            $props = @{ 
                Name=("[Build] " + $_.file);
                Elapsed =$([TimeSpan]::FromSeconds($_.elapsedSeconds)) 
            };

            $times += new-object PSObject -Property $props
        }

    $execTasks = select-xml $build.msbuild -XPath "//task[@name='Exec']"

    $execTasks.Node | 
        % {
            $cmd = select-xml $_ -XPath "./message[@level='high']/text()" 
            $first = $cmd.Node.InnerText | select -f 1

            [int] $seconds = $_.elapsedSeconds

            if ($seconds -gt 1) {

                $props = @{ 
                    Name=("[Exec] " + $first);
                    Elapsed =$([TimeSpan]::FromSeconds($seconds)) 
                };

                if ($first -match "BuildController") {
                    $index = $first.IndexOf("Step=") + 5;
                    $props["Name"] = ("[Build Controller] " + $first.Substring($index));
                }
                
                $times += new-object PSObject -Property $props
            }
        }

    $times | sort-object -Descending Elapsed
}

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

function stop-services ($server, $pattern = "^Drive.*") {
    $services = get-service -ComputerName $server | 
        where { $_.DisplayName -match $pattern } | select Name

    foreach ($svc in $services) {
        write-host "stopping $svc on $server"
        sc.exe \\$server stop "$svc"
    }
}

<#
    .SYNOPSIS
        Helpful scriptlet for recycling app pools.

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

<#
    .SYNOPSIS search a directory for a string
    .DESCRIPTION delegates to findstr but makes it a bit more friendly to use.
#>
function grep {
    Param(
        [Parameter()] [string] $pattern = "*.*",
        [Parameter(Mandatory = $true)] [string]$text
    )

    dir -File -Filter $pattern | % { 
        $result = findstr /N /R $text $_

        if ($result) {
            write-host $_.FullName -ForegroundColor White -NoNewLine
            write-host ": " -ForegroundColor DarkYellow
            
            $result | % { 
                write-host "   $_"-ForegroundColor Magenta
            }
        }
    }
}

function display-date ([datetime] $date) {
    $format = "MM/dd/yyyy HH:mm:ss"

    if ($date -ne [DateTime]::MinValue) {
        return $date.ToString($format)
    }
    
    return ""
}

function ccnet-status {
    $status = [xml] ( curl http://rchpwvadtmgm01.prod.corpint.net/ccnet/XmlServerReport.aspx )
    $projects = $status.CruiseControl.Projects.Project 
    $nextBuild = @{ Name="nextBuildTime"; Expression={ display-date $_.nextBuildTime } }
    $props = $projects |
        select name, activity, lastBuildStatus, lastBuildLabel, $nextBuild
    
    $props | format-color -colors @{ "Building" = "Blue"; "Broken" = "Red" }
}

function curl ([string] $url) {
    $client = new-object Net.WebClient; 
    $client.Proxy = $null;

    return $client.DownloadString($url)
} 

function wget ([string] $url) { 
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

function clear-iistemp {
    dir "C:\Windows\Microsoft.NET\Framework\v4.0.30319\Temporary ASP.NET Files" | rm -Force -Recurse
    dir "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Temporary ASP.NET Files" | rm -Force -Recurse
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

################## SQL STUFF ######################
add-type -AssemblyName "Microsoft.SqlServer.Smo, Version=11.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91, processorArchitecture=MSIL"

<#
    .DESCRIPTION Scripts all the user-defined stored procedures for a given server/database into the supplied output folder.
#>
function script-storedprocedures {
    Param(
        [Parameter(Mandatory = $true)] [string] $serverName,
        [Parameter(Mandatory = $true)] [string] $databaseName,
        [Parameter()] [string] $outputFolder
    )

    if (-not $outputFolder) {
        $outputFolder = $pwd
    }

    $server = new-object -TypeName "Microsoft.SqlServer.Management.Smo.Server" $serverName
    $database = $server.Databases.Item($databaseName)

    $scripter = new-object -TypeName "Microsoft.SqlServer.Management.Smo.Scripter" $server
    $scripter.Options.ScriptDrops = $true;
    $scripter.Options.ToFileOnly = $true;

    $database.StoredProcedures | 
        where { $_.Owner -ne "sys" -and -not($_.Name.StartsWith("sp_")) } |
            % { 
                $scripter.Options.FileName = [system.io.path]::combine($outputFolder, $_.Name + ".sql")
                $scripter.Script($_)
            }
}

##################   ALIASES   ####################
set-alias u update-svn
set-alias cleanup cleanup-svn
set-alias svndiff get-svnchanges
set-alias build build-solution
set-alias recycle recycle-apppool
set-alias lsapp list-apppool

set-alias fxcop "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Team Tools\Static Analysis Tools\FxCop\FxCopCmd.exe"
set-alias csc "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
set-alias vs2010 "C:\Program Files (x86)\Microsoft Visual Studio 10.0\Common7\IDE\devenv.exe"
set-alias vs2012 "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\devenv.exe"
set-alias ngen "C:\Windows\Microsoft.NET\Framework\v4.0.30319\ngen.exe"
set-alias edit "C:\Program Files\Sublime Text 2\sublime_text.exe"
set-alias msbuild "C:\Windows\Microsoft.Net\Framework\v4.0.30319\MSBuild.exe"
set-alias vstest "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe"


################# UPDATE PROMPT ####################
function prompt {
    write-host "$env:UserName@$env:ComputerName " -NoNewLine -ForegroundColor DarkGreen
    write-host $executionContext.SessionState.Path.CurrentLocation -ForegroundColor DarkYellow
    
    return "$ "
}

cd c:\development
cls
