<#
    takes a csv and partitions it into chunks
    of the given @size
#>
function chunk-file($file, [int]$size = 500) {
    $lines = get-content $file

    $i = 0;
    $low = 1;
    $count = $lines.length;
    $high = [math]::min($count, $size - 1);
    $leftPad = [math]::Log10($count / $size) + 1;

    $start = $file.lastIndexOf("\") + 1;
    $end = $file.lastIndexOf(".")
    $name = $file.substring($start, $end - $start);
    $header = @($lines[0])

    do {
        $i++;
        # ensures that we include the header.
        $slice = $header + $lines[$low..$high]
        $ordinal = "_" + $i.ToString().PadLeft($leftPad, "0");
        $chunkName = "chunks/$name" + $ordinal + ".csv"

        $slice | out-file $chunkName -Encoding ascii

        write-host "file written: $chunkName" -ForegroundColor Green

        if ($high -eq $count - 1) { break; }

        $low = $high + 1;
        $high = [math]::min($count - 1, $low + $size);
    } while ($true);

    write-host "$i file(s) exported!" -ForegroundColor Green
}