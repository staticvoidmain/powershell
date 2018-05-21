set-strictmode -off
add-type -AssemblyName System.Net.Http

<# todo: this just needs to be a module. #>
function __fail() {
  __inc fail_count

  $elapsed = ([datetime]::Now - $ctx.start).TotalMilliseconds
  $x = [char]0x2715

  write_line red "$x it $($ctx.name) $([int]$elapsed)ms";

  $ctx.errors | %{
    write_line red $_
  }

  # log it out to a file.
  $ctx.name | out-file -Append "errors.log"
  $ctx.errors | out-file -Append "errors.log"
  "`r`n`r`n" | out-file -Append "errors.log"
}

function __set($name, $value) {
  Set-Variable -Scope Script -Visibility Private -Name $name -Value $value
}

function __inc($name) {
  $value = (Get-Variable -Name $name).Value + 1
  Set-Variable -Scope Script -Visibility Private -Name $name -Value $value
}

function __createContext([string]$name) {
  $newContext =[pscustomobject] @{
    "ok" = $true;
    "name" = $name;
    "start" = [datetime]::Now;
    "end" = $null;
    "errors" = @();
  }

  __set ctx $newContext
}

function __onError($e) {
    $ctx.ok = $false;
    $ctx.errors = $e.Exception.Message

    if ($e.ErrorDetails) {
      $err = $e.ErrorDetails.Message | ConvertFrom-Json

      if (has-prop $err "InnerException") {
        $err = $err.InnerException
      }

      $ctx.errors += $err.ExceptionMessage
      $ctx.errors += $err.StackTrace
    }
}

# private variables.
__set verbose $false
__set indent ""
# not sure why these counts don't work, but the
# indent and verbose options do...
__set total 0
__set fail_count 0
__set pass_count 0
__set skip_count 0
__set assert_count 0
__set max_execution_time 500 #ms
__set fail_slow_tests $false
__set request_timeout_secs 2

# public interface
function set_filter($f) {
  __set filter $f
}

<# todo: more hooks #>
function set_pre_request_hook($hook) {
  __set pre_request_hook
}

function enable_verbose_output() {
  __set verbose $true
}

function disable_verbose_output() {
  __set verbose $false
}

<# prints a test summary and exits the script #>
function print_test_summary {
  write-host "`n`nSummary:"
  write-host -F green "[ Passed: $pass_count ]" -NoNewline
  write-host -F red "  [ Failed: $fail_count ]" -NoNewline
  write-host -F yellow "  [ Skipped: $skip_count ]"

  $exitCode = 0;

  if ($fail_count -gt 0) { $exitCode = -1 }

  exit $exitCode
}

function write_line ($f, $msg) {
  $line = "$indent$msg";
  write-host -F $f $line
}

function xdescribe([string]$name, [scriptblock]$block) {
  write_line cyan "DESCRIBE: $name"
  $skipped = $true;
  $block.Invoke();
  $skipped = $false;
}

function beforeEach ([scriptblock] $block) {
    $beforeEachSpec = $block;
}

function setup ([scriptblock] $block) {
  # todo: more with this.
  $block.Invoke();
}

function describe ([string]$name, [scriptblock]$block) {

  write_line cyan "$name"

  if ($filter -and -not ($name -match $filter)) {
    return;
  }

  # todo: double describe doesn't nest like it should.
  __set indent ($indent + "  ");

  try {
    $block.Invoke();
  } finally {
    __set indent ($indent.substring(0, $indent.Length - 2));
  }
}

function xit([string]$name,[scriptblock]$block) {
  __inc total
  __inc skip_count
  write_line yellow "SKIPPED: it $name"
}

function it([string] $name, [scriptblock]$block) {

  __set assert_count 0
  __inc total

  if ($skipped) {
    __inc skip_count
    write_line yellow "SKIPPED: $name"
    return;
  }

  try {
    __createContext $name

    $results = $block.Invoke();

    $ctx.end = [datetime]::Now;

    if ($ctx.ok) {
      # todo: fail the test if the timeout expires?
      # that just sets us up to do the stupid jasmine thing
      # where people set a high timeout and ignore the failure.
      $elapsed = [int]($ctx.end - $ctx.start).TotalMilliseconds

      __set pass_count ($pass_count + 1);

      $color = "green";
      $status = [char]0x2714 #check-mark

      if ($elapsed -gt $max_execution_time) {

        if ($fail_slow_tests) {
          __set pass_count ($pass_count - 1);
          __set fail_count ($fail_count + 1);

          $color = "red";
          $status = "TIMEOUT";
        } else {
          $color = "yellow";
          $status = "SLOW";
        }
      }
      elseif ($assert_count -eq 0) {
        $color = "yellow";
        $status = "INCONCLUSIVE";
      }

      write_line $color "$($status) $name  $($elapsed)ms";

      return;
    }
  }
  catch {
    $ctx.ok = $false;
    $ctx.errors += $_
  }

  return __fail
}

function has-prop ($obj, $prop) {
  return $err.psobject.properties[$prop] -ne $null;
}

function post ($url, $data) {

  if ($verbose) {
    write-host "POST $url"
    write-host ($data | ConvertTo-Json)
    write-host "`n"
  }

  try {
    $headers = @{
      "Content-Type" = "application/json";
    }

    $body = ConvertTo-Json $data
    $res = Invoke-WebRequest $url -Method POST -UseBasicParsing `
      -Body $body `
      -Headers $headers |
        select StatusCode, Content
  }
  catch [System.Net.Webexception] {
    __onError $_

    return $null
  }

  if ($verbose) {
    write-host "Status: $($res.StatusCode)"
    write-host "Content: $($res.Content)"
    write-host "`n"
  }

  return $res.Content | ConvertFrom-Json
}

function head ($url) {
  try {
    $res = Invoke-WebRequest $url -Method HEAD -UseBasicParsing |
        select StatusCode, Content
  }
  catch [System.Net.Webexception] {
    __onError $_
    return $null
  }

  return $res.Content | ConvertFrom-Json
}

function get ($url) {

  if ($verbose) {
    write_line white "GET $url"
  }

  try {
    $res = Invoke-WebRequest $url -Method GET -UseBasicParsing `
      -TimeoutSec $request_timeout_secs |
        select StatusCode, Content
  }
  catch [System.Net.Webexception] {
    __onError $_
    return $null
  }

  if ($verbose) {
    write-host "Status: $($res.StatusCode)"
    write-host "Content: $($res.Content)"
    write-host "`n"
  }

  # todo: what about status code?
  return $res.Content | ConvertFrom-Json
}

##########################
## Assertion Lib #########
##########################

<# assert an arbitrary expression returns true #>
function assert_expr ([string]$that, [scriptblock]$cond) {
  __inc assert_count

  $result = $cond.Invoke();

  if (-not($result)) {
    $ctx.ok = $false;
    $ctx.errors += "`n$($indent)ASSERT: '$that' $cond ";
  }
}

function assert_throws ([string]$when, [scriptblock]$expr) {
  __inc assert_count

  try {
    $expr.Invoke();
  }
  catch {
    return;
  }

  $ctx.ok = $false;
  $ctx.errors += "`nASSERT: '$when' expected $expr to throw";
}

function assert_lessThan($actual, $expected) {
  __set assert_count

  if (-not ($actual -lt $expected)) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual LESS_THAN $expected";
  }
}

function assert_lessThanEqual($actual, $expected) {
  __inc assert_count

  if (-not($actual -le $expected)) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual $expected";
  }
}

function assert_greaterThan($actual, $expected) {
  __inc assert_count

  if (-not($actual -gt $expected)) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual > $expected";
  }
}

function assert_greaterThanEqual($actual, $expected) {
  __inc assert_count

  if (-not($actual -ge $expected)) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual >= $expected";
  }
}

function assert_equal($actual, $expected) {
  __inc assert_count

  if (-not($actual -eq $expected)) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual == $expected";
  }
}

function assert_notEqual($actual, $expected) {
  __inc assert_count

  if (-not($actual -ne $expected)) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual != $expected";
  }
}

function assert_isNull($actual) {
  __inc assert_count

  if (-not $actual -eq $null) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual to be null";
  }
}

function assert_isNotNull($actual) {
  __inc assert_count

  if ($actual -eq $null) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual NOT to be null";
  }
}

function assert_isTruthy($actual) {
  __inc assert_count

  if (-not $actual) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual to be truthy";
  }
}

function assert_isFalsy($actual) {
  __inc assert_count

  if ($actual) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual  to be falsy";
  }
}

function assert_isMatch($actual, $pattern) {
  __inc assert_count

  $re = [regex]$pattern

  if (-not ($re.IsMatch($actual))) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected $actual to match $pattern";
  }
}

<# de-dupe checking #>
function assert_unique ($collection) {
  __inc assert_count

  $ids = new-object -TypeName System.Collections.Hashtable
  $unique = $true;

  foreach($_ in $collection) {
      if ($ids.ContainsKey($_)) {
         $unique = $false;
         break;
      }

      $ids.Add($_, 1);
  }

  if (-not $unique) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected [ $collection ] values to be UNIQUE";
  }
}

<# expects all the values to be a $expected #>
function assert_all ($collection, $expected) {
  __inc assert_count

  foreach ($actual in $collection) {
    if ($actual -ne $expected) {
      $ctx.ok = $false;
      $ctx.errors += "ASSERT: Expected each element of [ $collection ] to be $expected";
      break;
    }
  }
}

function assert_any ($collection, $expected) {
  __inc assert_count

  $match = $false;
  foreach ($actual in $collection) {
    if ($actual -eq $expected) {
      $match = $true;
      break;
    }
  }

  if (-not $match) {
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected at least one element of [ $collection ] to be $expected";
  }
}

function assert_none($collection, $expected) {
  __inc assert_count

  foreach ($actual in $collection) {
    if ($actual -eq $expected) {
      $ctx.ok = $false;
      $ctx.errors += "ASSERT: Expected [ $collection ] NOT to contain $expected";
      break;
    }
  }
}

<# asserts that only ONE value in the collection matches $expected #>
function assert_one($collection, $expected) {
  __inc assert_count

  $count = 0;

  foreach($i in $collection) {
    if ($i -eq $expected) { $count++; }
  }

  if ($count -ne 1) {
      $ctx.ok = $false;
      $ctx.errors += "ASSERT: Expected exactly ONE $expected in [ $collection ]";
    }
}

function assert_ordered ($c, [string] $direction = "asc") {
  __inc assert_count

  if ($c -and $c.Length) {

    $fail = $false;
    for ($i = 0; $i -lt $c.Length; $i++) {
      if ($i -gt 0) {
        $curr = $c[$i];
        $prev =  $c[$i - 1];

        if ($direction -eq "asc") {
          if ($prev -gt $curr) {
            $fail = $true;
          }
        } else {
          if ($prev -lt $curr) {
            $fail = $true;
          }
        }
      }
    }

    if ($fail) {
      $ctx.ok = $false;
      $ctx.errors += "ASSERT: Expected $c to be ordered $direction";
    }
  }
}

function assert_isDefined ($obj, $prop) {
  __inc assert_count

  if (-not $obj.psobject.properties[$prop]){
    $ctx.ok = $false;
    $ctx.errors += "ASSERT: Expected object to have property '$prop'";
  }
}
