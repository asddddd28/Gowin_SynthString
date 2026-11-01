param(
    [string]$Port='COM4',
    [ValidateRange(1,120)][int]$Seconds=10,
    [string]$Label='capture',
    [string]$StopFile=''
)
$ErrorActionPreference='Stop'
$reportDir=Join-Path $PSScriptRoot 'reports'
[IO.Directory]::CreateDirectory($reportDir)|Out-Null
$prefix=Join-Path $reportDir ("encoder_"+$Label+'_'+(Get-Date -Format yyyyMMdd_HHmmss))
$portObject=[IO.Ports.SerialPort]::new($Port,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$portObject.DtrEnable=$false
$portObject.RtsEnable=$false
$portObject.Handshake=[IO.Ports.Handshake]::None
$portObject.ReadBufferSize=65536
$portObject.ReadTimeout=200
$raw=[Collections.Generic.List[byte]]::new()
$liveFile=[IO.File]::Open("$prefix.live.bin",[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
"LiveFile=$prefix.live.bin"
try {
    $portObject.Open()
    $portObject.DiscardInBuffer()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($watch.Elapsed.TotalSeconds -lt $Seconds){
        if($StopFile -and (Test-Path -LiteralPath $StopFile)){break}
        $count=$portObject.BytesToRead
        if($count -gt 0){
            $chunk=[byte[]]::new($count)
            $got=$portObject.Read($chunk,0,$count)
            if($got -gt 0){
                $raw.AddRange([byte[]]$chunk[0..($got-1)])
                $liveFile.Write($chunk,0,$got)
                $liveFile.Flush()
            }
        }
        Start-Sleep -Milliseconds 10
    }
} finally {
    $portObject.Close()
    $portObject.Dispose()
    $liveFile.Dispose()
}
[IO.File]::WriteAllBytes("$prefix.bin",$raw.ToArray())
$text=[Text.Encoding]::ASCII.GetString($raw.ToArray())
$matches=[regex]::Matches($text,'E([1-5]) A([0-3]) F([0-3]) Q([0-9A-F]{4}) P([0-9A-F]{4}) N([0-9A-F]{4}) X([0-9A-F]{4})\r\n')
$records=@(foreach($m in $matches){
    $q=[Convert]::ToInt32($m.Groups[4].Value,16)
    if($q -ge 32768){$q-=65536}
    [pscustomobject]@{
        Encoder=[int]$m.Groups[1].Value;Raw=[int]$m.Groups[2].Value;Filtered=[int]$m.Groups[3].Value
        Position=$q;Positive=[Convert]::ToInt32($m.Groups[5].Value,16)
        Negative=[Convert]::ToInt32($m.Groups[6].Value,16);Invalid=[Convert]::ToInt32($m.Groups[7].Value,16)
    }
})
$sequenceErrors=0;$invariantErrors=0;$previous=0
foreach($r in $records){
    if($previous -and $r.Encoder -ne ($previous%5+1)){$sequenceErrors++}
    if(($r.Position -band 65535) -ne (($r.Positive-$r.Negative) -band 65535)){$invariantErrors++}
    $previous=$r.Encoder
}
$stats=@(foreach($channel in 1..5){
    $rows=@($records|Where-Object Encoder -eq $channel)
    if($rows.Count){
        $first=$rows[0];$last=$rows[-1]
        $posDelta=($last.Positive-$first.Positive) -band 65535
        $negDelta=($last.Negative-$first.Negative) -band 65535
        [pscustomobject]@{
            Encoder=$channel;Samples=$rows.Count;RawStates=(@($rows.Raw|Sort-Object -Unique)-join ',')
            FinalPosition=$last.Position;PositiveDelta=$posDelta;NegativeDelta=$negDelta
            InvalidDelta=(($last.Invalid-$first.Invalid)-band 65535)
            FinalPositive=$last.Positive;FinalNegative=$last.Negative;FinalInvalid=$last.Invalid
        }
    }
})
$summary=[ordered]@{
    Port=$Port;Baud=115200;Seconds=$watch.Elapsed.TotalSeconds;Bytes=$raw.Count;ValidRecords=$records.Count
    SequenceErrors=$sequenceErrors;InvariantErrors=$invariantErrors;Channels=$stats.Count
    UnmatchedBytes=($raw.Count-34*$records.Count)
    TransportPass=($records.Count -gt 0 -and $stats.Count -eq 5 -and $sequenceErrors -eq 0 -and $invariantErrors -eq 0)
    Stats=$stats;RawFile="$prefix.bin"
}
$records|Export-Csv "$prefix.csv" -NoTypeInformation -Encoding utf8
$summary|ConvertTo-Json -Depth 6|Set-Content "$prefix.json" -Encoding utf8
"Report=$prefix.json"
"Port=$Port bytes=$($raw.Count) records=$($records.Count) sequence_errors=$sequenceErrors invariant_errors=$invariantErrors"
$stats|Format-Table -AutoSize
if(!$summary.TransportPass){throw 'Encoder capture transport checks failed; inspect saved evidence.'}
