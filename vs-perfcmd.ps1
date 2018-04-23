$env:PATH += "C:\Program Files (x86)\Microsoft Visual Studio 14.0\Team Tools\Performance Tools;"

function instrument-binaries ([string] $basePath, $assemblies) {
 
    push-location $basePath
 
    if (-not (test-path ( where.exe VsInstr.exe ))) {
        write-host "VsInstr.exe is not installed!"
    } else {
        $assemblies = get-childitem $path | where { $expr.IsMatch($_.Name) } | select Name

        foreach ($instr in $assemblies) {
            write-host "vsinstr.exe $instr"
            VsInstr.exe $instr /ExcludeSmallFuncs
        }
    }
 
    pop-location
}

function begin-profiling ( [string] $session, [string] $report_path ) {
    
    if (-not (test-path $report_path )) {
        mkdir "$report_path"| out-null
    }
 
    $env:_NT_SYMBOL_PATH = "srv*C:\mssymbols*http://msdl.microsoft.com/downloads/symbols"
   
    # make sure the profiler isn't already running.
    VsPerfCmd.exe /Status
 
    if ($LastExitCode -ne 0) {
        $name = $session + [DateTime]::Now.ToString("MM-dd-yyyy-hh-mm")
        $report = [system.io.path]::combine($report_path, ($name + ".vsp"))
 
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

# todo: process results with vsperfreport