<# I really miss linux... :( #>
function top {
  ps | select name, id, vm, cpu | sort -desc cpu | select -f 10 | ft
}
