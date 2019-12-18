<# I really miss linux... :( #>
function top {
  ps | select name, id, vm, cpu | sort -desc cpu | select -f 10 | ft
}

# some commands like query user output "human readable" stdout
# but windows doesn't have a nice awk-like thing built in
# so this is that.
function from_column_aligned_output([string[]] $lines) {
  $headers = $lines[0];

  if ($lines.Length -eq 1) { return; }

  # extract headers and offsets
  $columns = @();
  $begin = 0; 
  $end = 0;
  $len = $headers.Length;
  while ($true) {
    # seek column begin
    $begin = $end;
    for (; $begin -lt $len; $begin++) {
      if (-not [char]::IsWhiteSpace($headers[$begin])) {
        break;
      }
    }

    # seek column end
    $end = $begin;
    $consecutive = 0;
    for (; $end -lt $len; $end++) {
      if ([char]::IsWhiteSpace($headers[$end])) {
        $consecutive++;
      }

      if ($consecutive -eq 2) {
        break;
      }
    }

    $columns += new-object psobject -Property @{
      "begin" = $begin;
      "name" = $headers.Substring($begin, $end - $begin).Trim();
    };

    if ($end -eq $len) {
      break;
    }
  }

  $output = @();
  for ($i = 1; $i -lt $lines.Length; $i++) {
    $line = $lines[$i];
    $o = new-object psobject;
    for ($c = 0; $c -lt $columns.Length; $c++) {
      $col = $columns[$c];
      $end = if ($c -eq $columns.Length - 1) { $len } else { $columns[$c+1].begin }
      $size = $end - $col.begin;
      $value = $line.Substring($col.begin, $size).Trim();
      $o | add-member -MemberType NoteProperty -Name $col.name -Value $value;
    }

    $output += $o;
  }

  return $output;
}
