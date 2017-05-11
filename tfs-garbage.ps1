
# home for all this TFS VC garbage

function commit (
    $files = ".",   # . or named items
    $comment,       # a nice string, required
    [switch] $recursive = $true, 
    [switch] $bypass) {

    $cmd = "tf checkin $files /comment:$comment"
    
    if ($recursive) {
        cmd += " /r"
    }

    if ($bypass) {
        $cmd += " /noprompt /bypass";
    }

    Invoke-Expression $cmd
}

function tf-undo ($f) {
    tf undo $f /noprompt 
}

function tf-diff { 
  tf diff . /r /format:unified /type:text /ignorespace | color-udiff
}

function color-udiff {
  Param(
    [Parameter(
        Position=0, 
        Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
    [Alias('l')] [String[]] $lines)

    process {
      foreach ($line in $lines) {
        if ($line.length -gt 1) {
          $start = $_.substring(0, 1)
          switch ($start) {
            "+" { ansi green $line; break; }
            "-" { ansi red $line; break; }
            "@" { ansi magenta $line; break; }
            default { $line; break; }
          }
        } else {
          $line;
        }
      }
    }
}

function ansi ($color, $text) {
    $c = [char]0x001b # the magic escape

    switch ($color.toLower()) {
      "red"     { return "${c}[31m${text}${c}[39m"; }
      "green"   { return "${c}[32m${text}${c}[39m"; }
      "magenta" { return "${c}[35m${text}${c}[39m"; }
      default   { return "${text}"; }
    }
}
