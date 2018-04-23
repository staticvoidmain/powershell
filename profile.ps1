$ErrorActionPreference = "Stop"
set-strictmode -Version Latest

function prompt {
    $loc = ($pwd).Path.Replace("Microsoft.PowerShell.Core/FileSystem::", "").Replace("$HOME", "~").Replace("\", "/")

    write-host "$env:UserName@$env:ComputerName " -NoNewLine -ForegroundColor DarkGreen
    write-host $loc -ForegroundColor DarkYellow
    
    # just to keep things from going weird.
    [Console]::ForegroundColor = [System.ConsoleColor]::White;

    return "$ "
}

# IMPORTS
. c:\dev2\scripts\tf-helpers.ps1

# Chocolatey profile
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

$env:EDITOR = "sublime_text.exe";

$env:PATH += ";" # symetry
$env:PATH += "c:\program files\sublime text 3\;"
$env:PATH += "c:\tools;"
$env:PATH += "C:\Program Files\Java\jre1.8.0_131\bin;"
$env:PATH += "c:\windows\system32\inetsrv;"
$env:PATH += "c:\program files (x86)\msbuild\14.0\bin\;"
$env:PATH += "C:\Program Files (x86)\Microsoft Visual Studio 14.0\vc\bin;"
$env:PATH += "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer;"
$env:PATH += "C:\Program Files (x86)\Windows Kits\8.0\Debuggers\x64;"
$env:PATH += "C:\Program Files (x86)\Windows Kits\8.1\bin\x86;"
$env:PATH += "C:\Program Files (x86)\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.7 Tools;"
$env:PATH += "C:\Program Files (x86)\WinMerge;"
$env:PATH += "C:\tools\fd;"
$env:PATH += "C:\windows\microsoft.net\framework64\v4.0.30319;";

$env:JAVA_HOME = "C:\Program Files\Java\jre1.8.0_131"

# everyone should get their own API key.
$env:OCTODEPLOY_API_KEY = "API-UVNEV5RMWZYTHEKCAPG9UZFHO"

# command default value extensions.
# interestingly, powershell defines += as merge(dict, dict)
$PSDefaultParameterValues += @{
  'Measure-Object:Average' = $true;
  'Measure-Object:Sum' = $true;
  'Measure-Object:Maximum' = $true;
  'ConvertTo-Csv:NoTypeInformation' = $true;
  'ConvertTo-Json:NoTypeInformation' = $true;
  'Invoke-WebRequest:UseBasicParsing' = $true;
  'Invoke-WebRequest:UseDefaultCredentials' = $true;
  'Invoke-RestRequest:UseDefaultCredentials' = $true;
  'Out-File:Encoding' = 'utf8';
  'Get-History:Count' = 25;
}

$PSMailServer = "10.20.11.211"

function edit {
  [cmdletbinding()]
  param(
    [parameter(ValueFromPipeline)]
    [string[]]$files
  )

  process {
    foreach ($file in $files) {
      & $env:EDITOR $file
    }
  }
}

function ConvertTo-HexString($bytes) {
    return [string]::Join("", `
      ($bytes | %{ $_.ToString("x2").ToLower() }))
}

function clean-solution ($sln, [switch] $release) {
    $config = if ($release) { "Release" } else {"Debug"}

    msbuild $sln /t:Clean /v:m /nr:true /p:Configuration=$config /m /nologo
}

function build-solution ($sln, [switch] $release, [switch] $verbose) {
    nuget restore $sln
    $v = if ($verbose) { "v" } else { "m" }

    if ($release) {
      msbuild $sln /t:Build /v:$v /nr:true /m /p:Configuration=Release /nologo
      return;
    }
    
    msbuild $sln /t:Build /v:$v /nr:true /m /p:RunCodeAnalysis=false /p:CodeAnalysisRuleSet='' /p:Configuration=Debug /nologo
}

<# unified diff #>
function udiff($left, $right) { git diff --no-index -w --ignore-blank-lines $left $right }

# symlink stuff, could also just delete the directory.
# using powershell.
function mklink { cmd /c mklink $args }

function rmlink { cmd /c rmlink $args }

function disk-usage ($p) { du64.exe $p }

function rel-path {
  [cmdletbinding()]
  param(
    [parameter(ValueFromPipeline)]
    [string[]]$stdin
  )
  begin { 
    $d = $pwd.toString().Replace("Microsoft.PowerShell.Core\FileSystem::", "")
    $len = $d.length;

    if (-not($d.EndsWith("\"))) {
      $len++;
    }
  }
  process {
    foreach ($p in $stdin) {
      $p.substring($len).replace("\", "/");
    }
  }
}

function list-directory {
  # okay, technically this only makes sense in the context of a FILE
  if ((get-location).Provider.Name.EndsWith("FileSystem")) {
    
    $dir = [system.io.fileattributes]::Directory
    $hidden = [system.io.fileattributes]::Hidden
    $symlink = [system.io.fileattributes]::ReparsePoint
    $argv = [string]::Join(" ", $args)

    Invoke-Expression "Get-ChildItem $argv -Force" | % {
      $c = "white"
      
      if ($_.Attributes -band $hidden) {
        $c = "darkgray"
      }
      elseif ($_.Attributes -band $symlink) {
        $c = "cyan"
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

      write-host -NoNewLine $line
      $name = rel-path $_.FullName;

      write-host -F $c $name
    }
  } 
  else {
    gci
  }
}

<# helper for ls to display human readable sizes #>
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

function fe ($search) {

  if ($search) {
    fd --type f | fzf -q "$search" | edit
    return;
  }

  fd --type f | fzf | edit
}

function cdf ($search) {
  if ($search) {
    fd --type d | fzf -q "$search"| cd
    return;
  }

  fd --type d | fzf | cd
}

function ansi ($color, $text) {
    $c = [char]0x001b # the magic escape

    switch ($color.toLower()) {
      "red"     { return "${c}[31m${text}${c}[39m"; }
      "green"   { return "${c}[92m${text}${c}[39m"; }
      "magenta" { return "${c}[35m${text}${c}[39m"; }
      "cyan"    { return "${c}[94m${text}${c}[39m"; }
      "purple"  { return "${c}[35m${text}${c}[39m"; }
      default   { return "${text}"; }
    }
}

function watch-mem {
  param($p)

  $prev = (get-process -id $p).PrivateMemorySize;
  while ($true) {
    
    $curr = (get-process -id $p).PrivateMemorySize;
    $ts = [datetime]::now.toString("HH:mm:ss,fff")

    $diff = $curr - $prev;
    $delta = if ($diff -ge 0) { "+" + $diff.ToString() } else { $diff.ToString() }

    switch ($curr) {
      { $_ -gt 1tb } { $line = ("{0,4:n1} T" -f ($_ / 1tb))}
      { $_ -gt 1gb } { $line = ("{0,4:n1} G" -f ($_ / 1gb)) }
      { $_ -gt 1mb } { $line = ("{0,4:n1} M" -f ($_ / 1mb)) }
      { $_ -gt 1kb } { $line = ("{0,4:n1} K" -f ($_ / 1Kb)) }
      default { $line = "  {0,4:0} B" -f $_ } 
    }

    $prev = $curr;
    write-host "$ts  $line ( $delta )"
    sleep -Seconds 3;
  }
}

function exec-sql ($srv, $db, $s) {

    $ts = [datetime]::now.toString("HH:mm:ss,fff")
    $file = (resolve-path $s).Path

    write-host -F green "$ts  $file on $db"
    sqlcmd -b -S $srv -d $db -i $file | % {
        $ts = [datetime]::now.toString("HH:mm:ss,fff")
        "$ts  $_"
    };

    if ($LASTEXITCODE -ne 0) {
        throw "Error running $s"
    }
}

function howdoi ($what) {
  switch($what) {
    "even" { "If you just can't even... maybe go for a walk." }
    "bcp" {
      write-host "export a table:"
      write-host ""
      write-host "`tbcp <table> out <file-name> -S <server> -d <database> -T -w"
      
      write-host ""
      write-host "dump a format:"
      write-host "`tbcp tableName format nul -c -t '|' -r '\n' -f formatName.fmt -S serverName -d databaseName -T"
      
      write-host ""
      write-host "dump a query:"
      write-host "`tbcp `"select RecoveryID from dbo.Recovery where CollectedAmount > 0 and DateReceived is null`" queryout recovery-ids -S AG_AP01 -d DealerRecovery -T -w"
      
      write-host ""
      write-host "ingest data"
      write-host "`tbcp <tableName> in <file> -S <server> -d <db> -w -T"
    }
  }
}

function indent-xml ($x) {
  $doc = [xml] $x;
  
  try {
    $writer = new-object -TypeName "System.Xml.XmlTextWriter" ([System.Console]::Out)
  
    $doc.WriteContentTo($writer);
  }
  finally {
    $writer.Dispose();
  }
}

function get-windows-auth () {
    $user = $env:UserDomain + "\" + $env:UserName
    
    $local_windows_auth_credential = Get-Variable windows_auth_credential -ErrorAction Ignore

    if (-not($local_windows_auth_credential)) {
       $local_windows_auth_credential = get-credential -UserName $user -Message "Get windows auth token:"

       set-variable -Scope Global -Value $local_windows_auth_credential -Name windows_auth_credential
    }

    $local_windows_auth_credential
}

<# 
  .description poor-man's word-count implementation
  .outputs line_count{TAB}word_count{TAB}char_count
  .parameter chars output the char count only.
#>
function wc {
  [cmdletbinding()]
  param(
    [parameter(ValueFromPipeline)]
    [string[]]$stdin,

    [alias("m")][switch]$chars,
    [alias("l")][switch]$lines,
    [alias("w")][switch]$words
  )

  begin { 
    $line_count = 0;
    $word_count = 0;
    $char_count = 0;
    $flags = $chars -or $lines -or $words
  }
  
  process {
    foreach ($l in $stdin) {
      $line_count++;

      for ($i = 0; $i -lt $l.length; $i++) {
        if ($l[$i] -ne ' ' -and ($i-1 -eq -1 -or $l[$i-1] -eq ' ')) {
          $word_count++;
        }
      }

      $char_count += $l.length;
    }
  }

  end {
    if (-not($flags)) {
      write-host "$line_count`t$word_count`t$char_count"
    }
    else {
      $parts = @()
      if ($lines) {
        $parts += $line_count
      }

      if ($words) {
        $parts += $word_count;
      }

      if ($chars) {
        $parts += $char_count;
      }

      write-host 
    }
  }
}

function download-file {
  [cmdletbinding()]
  param(
    [parameter(ValueFromPipeline)]
    [string[]] $urls
  )

  begin {
    $client = new-object -TypeName system.net.webclient
    $base = [string] $pwd.Path
  }

  process {
    $name = [system.io.path]::GetFileName($_);
    $complete = [guid]::newguid();

    Register-ObjectEvent $client DownloadProgressChanged -action {
        $status = "{0} of {1}" -f $eventargs.BytesReceived, $eventargs.TotalBytesToReceive;

        Write-Progress -Activity "Downloading $name" -Status $status -PercentComplete $eventargs.ProgressPercentage;
    } | out-null

    Register-ObjectEvent $client DownloadFileCompleted -SourceIdentifier $complete | out-null

    $client.DownloadFileAsync($url, $path)
    Wait-Event -SourceIdentifier $complete | out-null

    $path
  }

  end {
    $client.Dispose()
  }
}

function tls-fix () {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function get-locationstack {
  get-location -stack
}

function tail ($file) {
  gc $file -Last 10 -Wait
}

# todo: delay each pulse?
# or just initially?
function delay {
  [cmdletbinding()]
  param(

    [int] $seconds = 0,

    [parameter(ValueFromPipeline)]
    [object[]] $pipe
  )

  begin { sleep -seconds $seconds }
  
  process {
    foreach ($val in $pipe) {
      $val
    }
  }
}

# schedule something to happen on a set interval.
function interval ($timeout = 10, [scriptblock] $block) {
  while ($true) {
    sleep -seconds $timeout
    $block.Invoke();
  }
}

# poor man's grep / xargs
function match {
  [cmdletbinding()]
  param(
    [string] $pattern,

    [parameter(ValueFromPipeline)]
    [string[]]$lines
  )

  begin {
    # todo: maybe validate the file extensions or something
    # since 7z seems to care.
    $re = [regex]::new($pattern, 'Compiled,IgnoreCase');
  }

  process {
    $m = $re.Match($_);
    
    if ($m.Success) {
      if ($m.Groups.Length -gt 1) {
        $len = $m.Groups.Count
        $m.Groups[1..($len-1)].Value -join "`t"
      }
    }
  }
}

function unzip($f) {
  7z.exe x $f
}

function zip {
  [cmdletbinding()]
  param(
    [string] $archive,

    [parameter(ValueFromPipeline)]
    [string[]]$files
  )

  begin {
    # todo: maybe validate the file extensions or something
    # since 7z seems to care.
    $file_list = "";
  }

  process {
    foreach ($f in $files) {

      $file_list += "`"$f`" ";
    }
  }

  end {
    $cmd = "7z.exe a -y -mmt $archive $file_list"
    Write-Host $cmd
    Invoke-Expression $cmd
  }
}

# go ALLL the way back.
function go-back($n = 1) {
  while ($n-- -gt 0) { 
    try { popd; }
    catch {} 
  }
}

set-alias locate "where.exe"
set-alias cd Push-Location -Option AllScope
set-alias ls list-directory -Option AllScope
set-alias wget download-file -Option AllScope

set-alias curl "C:\ProgramData\chocolatey\bin\curl.exe" -Option AllScope

set-alias hist get-history
set-alias gls get-locationstack
set-alias b go-back
set-alias du disk-usage
set-alias tg tf-get
set-alias ts tf-stat
set-alias td tf-diff
set-alias th tf-hist
set-alias commit tf-commit
set-alias checkin tf-commit
set-alias clean clean-solution
set-alias build build-solution
set-alias watch watch-solution
set-alias edmgen "C:/Windows/Microsoft.NET/Framework64/v4.0.30319/EdmGen.exe"
set-alias nunit "c:/tools/nunit/nunit-console/nunit3-console.exe"
set-alias ih Invoke-History
set-alias ngen "C:/Windows/Microsoft.NET/Framework64/v4.0.30319/ngen.exe"
set-alias ngen32 "C:/Windows/Microsoft.NET/Framework/v4.0.30319/ngen.exe"
set-alias sqlcmd "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\sqlcmd.exe"
set-alias vstest "C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe"
set-alias bcp "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\bcp.exe"
set-alias vs2017 "C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\devenv.exe"

cd c:\dev2