@echo off & powershell -NoProfile -ExecutionPolicy Bypass -Command "$base='%~dp0'; $t=[IO.File]::ReadAllText('%~f0'); $m='#PS'+'START'; iex $t.Substring($t.IndexOf($m)+$m.Length)" & pause & exit /b
#PSSTART
$ErrorActionPreference = 'Stop'
$reportsDir = Join-Path $base 'Reports'
$outDir     = Join-Path $base 'Combined Reports'
$passIcon   = [string][char]0x2705
$failIcon   = [string][char]0x274C

function Clean([string]$s) {
    $s = [regex]::Replace($s, '<[^>]+>', ' ')
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    return ([regex]::Replace($s, '\s+', ' ')).Trim()
}

function Esc([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }

function Norm([string]$w) {
    $u = $w.ToUpper()
    if ($u -in @('SUCCESS','PASSED','PASS')) { return 'PASSED' }
    if ($u -in @('FAILED','FAILURE','FAIL','ERROR')) { return 'FAILED' }
    return 'UNKNOWN'
}

function Badge([string]$s) {
    $c = switch ($s) { 'PASSED' {'success'} 'FAILED' {'danger'} default {'secondary'} }
    return '<span class="badge bg-' + $c + '">' + $s + '</span>'
}

function Parse-Report([string]$path) {
    $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $fileName = [IO.Path]::GetFileNameWithoutExtension($path)
    $list = New-Object System.Collections.ArrayList

    $ms = [regex]::Matches($raw, '(?s)<button([^>]*)>(.*?)</button>')
    for ($i = 0; $i -lt $ms.Count; $i++) {
        if ($ms[$i].Groups[1].Value -notmatch 'data-bs-toggle="collapse"') { continue }

        $header = Clean $ms[$i].Groups[2].Value
        if ($header -notmatch ':\s*(SUCCESS|FAILED|PASSED|FAILURE|ERROR)\s*$') { continue }

        $segStart = $ms[$i].Index + $ms[$i].Length
        $segEnd = $raw.Length
        if ($i + 1 -lt $ms.Count) { $segEnd = $ms[$i + 1].Index }
        $seg = $raw.Substring($segStart, $segEnd - $segStart)

        $name = $header
        $status = 'UNKNOWN'
        if ($header -match '^(.*?)\s*:\s*(\w+)\s*$') {
            $name = $matches[1]
            $status = Norm $matches[2]
        }

        $dur = ''
        if ($seg -match 'Duration:\s*([^<\r\n]+)') { $dur = $matches[1].Trim() }

        $st = ''
        if ($seg -match '(?s)<time[^>]*>(.*?)</time>') { $st = Clean $matches[1] }

        $props = New-Object System.Collections.ArrayList
        foreach ($m in [regex]::Matches($seg, '(?s)<tr>\s*<td>(.*?)</td>\s*<td>(.*?)</td>\s*</tr>')) {
            [void]$props.Add([pscustomobject]@{ K = (Clean $m.Groups[1].Value); V = (Clean $m.Groups[2].Value) })
        }

        $steps = New-Object System.Collections.ArrayList
        $parts = $seg -split 'class="step-item'
        for ($k = 1; $k -lt $parts.Count; $k++) {
            $p = $parts[$k]
            $hdr = ''
            if ($p -match '(?s)class="step-header[^"]*"[^>]*>(.*?)</div>') { $hdr = $matches[1] }
            $sStatus = 'UNKNOWN'
            if ($hdr.Contains($passIcon)) { $sStatus = 'PASSED' }
            elseif ($hdr.Contains($failIcon)) { $sStatus = 'FAILED' }
            $nm = ''
            if ($p -match '(?s)class="step-name">(.*?)</span>') { $nm = Clean $matches[1] }
            $bd = ''
            if ($p -match '(?s)badge[^"]*">(.*?)</span>') { $bd = Clean $matches[1] }
            [void]$steps.Add([pscustomobject]@{ Name = $nm; Status = $sStatus; Duration = $bd })
        }

        $failedSteps = @($steps | Where-Object { $_.Status -eq 'FAILED' }).Count
        [void]$list.Add([pscustomobject]@{
            Name = $name; Status = $status; Duration = $dur; Start = $st; File = $fileName
            Props = $props; Steps = $steps; StepsTotal = $steps.Count; StepsFailed = $failedSteps
        })
    }

    # Fallback: no flow header found, use the top-level result
    if ($list.Count -eq 0) {
        $status = 'UNKNOWN'
        if ($raw -match 'Test Result:\s*(\w+)') { $status = Norm $matches[1] }
        $title = $fileName
        if ($raw -match '(?s)<title>(.*?)</title>') { $title = Clean $matches[1] }
        [void]$list.Add([pscustomobject]@{
            Name = $title; Status = $status; Duration = ''; Start = ''; File = $fileName
            Props = (New-Object System.Collections.ArrayList)
            Steps = (New-Object System.Collections.ArrayList)
            StepsTotal = 0; StepsFailed = 0
        })
    }
    return $list.ToArray()
}

function Build-Flow($fl, [string]$fid) {
    $propHtml = ''
    foreach ($p in $fl.Props) {
        $propHtml += '<tr><td>' + (Esc $p.K) + '</td><td>' + (Esc $p.V) + '</td></tr>'
    }
    if ($propHtml -eq '') { $propHtml = '<tr><td colspan="2" class="text-muted">No properties</td></tr>' }

    $stepHtml = ''
    $n = 0
    foreach ($st in $fl.Steps) {
        $n++
        $icon = '-'
        if ($st.Status -eq 'PASSED') { $icon = $passIcon }
        elseif ($st.Status -eq 'FAILED') { $icon = $failIcon }
        $cls = ''
        if ($st.Status -eq 'FAILED') { $cls = ' class="table-danger"' }
        $stepHtml += '<tr' + $cls + '><td>' + $n + '</td><td>' + $icon + '</td><td>' +
            (Esc $st.Name) + '</td><td class="text-end">' + (Esc $st.Duration) + '</td></tr>'
    }
    if ($stepHtml -eq '') { $stepHtml = '<tr><td colspan="4" class="text-muted">No steps</td></tr>' }

    $head = '<summary class="card-header d-flex justify-content-between align-items-center flex-wrap gap-2" style="cursor:pointer">' +
        '<span><strong>' + (Esc $fl.Name) + '</strong> <small class="text-muted ms-2">' +
        $fl.StepsTotal + ' steps, ' + $fl.StepsFailed + ' failed</small></span>' +
        '<span>' + (Badge $fl.Status) + '</span></summary>'

    return '<details id="' + $fid + '" class="card mb-3 flow-detail" data-status="' + $fl.Status + '">' + $head +
        '<div class="card-body">' +
        '<p class="mb-2"><strong>Duration:</strong> ' + (Esc $fl.Duration) +
        ' &nbsp; <strong>Start:</strong> ' + (Esc $fl.Start) + '</p>' +
        '<h6 class="mt-3">Properties</h6>' +
        '<div class="table-responsive"><table class="table table-sm table-bordered">' +
        '<thead><tr><th>Property</th><th>Value</th></tr></thead><tbody>' + $propHtml + '</tbody></table></div>' +
        '<h6 class="mt-3">Steps</h6>' +
        '<div class="table-responsive" style="max-height:500px;overflow-y:auto">' +
        '<table class="table table-sm table-striped"><thead><tr><th>#</th><th></th><th>Step</th>' +
        '<th class="text-end">Time</th></tr></thead><tbody>' + $stepHtml + '</tbody></table></div>' +
        '</div></details>'
}

function Build-Page($reports, [string]$title) {
    $allFlows = @()
    foreach ($r in $reports) { $allFlows += @($r.Flows) }
    $totalFlows  = $allFlows.Count
    $passedFlows = @($allFlows | Where-Object { $_.Status -eq 'PASSED' }).Count
    $failedFlows = @($allFlows | Where-Object { $_.Status -eq 'FAILED' }).Count
    $singleCount = @($reports | Where-Object { @($_.Flows).Count -eq 1 }).Count
    $multiCount  = @($reports | Where-Object { @($_.Flows).Count -gt 1 }).Count

    $passRate = '0.0'
    $failRate = '0.0'
    if ($totalFlows -gt 0) {
        $passRate = ($passedFlows / $totalFlows * 100).ToString('0.0')
        $failRate = ($failedFlows / $totalFlows * 100).ToString('0.0')
    }

    $repRows  = New-Object System.Text.StringBuilder
    $sections = New-Object System.Text.StringBuilder
    $ri = 0
    foreach ($r in $reports) {
        $ri++
        $flows = @($r.Flows)
        $n  = $flows.Count
        $rp = @($flows | Where-Object { $_.Status -eq 'PASSED' }).Count
        $rf = @($flows | Where-Object { $_.Status -eq 'FAILED' }).Count
        $rs = 'UNKNOWN'
        if ($rf -gt 0) { $rs = 'FAILED' } elseif ($rp -gt 0) { $rs = 'PASSED' }

        $kindKey = 'none'; $kindText = 'No flows'; $kindColor = 'secondary'
        if ($n -eq 1) { $kindKey = 'single'; $kindText = 'Single flow'; $kindColor = 'info' }
        elseif ($n -gt 1) { $kindKey = 'multi'; $kindText = 'Multiple flows (' + $n + ')'; $kindColor = 'primary' }
        $kindBadge = '<span class="badge bg-' + $kindColor + '">' + $kindText + '</span>'

        $rid = 'report-' + $ri
        $fileEsc = Esc $r.FileName

        [void]$repRows.Append('<tr class="rep-row" data-type="' + $kindKey + '" data-status="' + $rs + '">' +
            '<td>' + $ri + '</td>' +
            '<td><a href="#' + $rid + '">' + $fileEsc + '</a></td>' +
            '<td>' + $kindBadge + '</td>' +
            '<td>' + $n + '</td><td>' + $rp + '</td><td>' + $rf + '</td>' +
            '<td>' + (Badge $rs) + '</td></tr>')

        $body = ''
        if ($n -eq 0) {
            $body = '<p class="text-muted mb-0">No flows were found in this report.</p>'
        } else {
            $j = 0
            foreach ($fl in $flows) {
                $j++
                $body += Build-Flow $fl ($rid + '-flow-' + $j)
            }
        }

        $secHead = '<summary class="card-header d-flex justify-content-between align-items-center flex-wrap gap-2" style="cursor:pointer">' +
            '<span><strong>' + $fileEsc + '</strong></span>' +
            '<span>' + $kindBadge + ' ' + (Badge $rs) +
            ' <small class="text-muted ms-2">passed ' + $rp + ' / failed ' + $rf + '</small></span></summary>'

        [void]$sections.Append('<details id="' + $rid + '" class="card mb-4 rep-section" data-type="' + $kindKey +
            '" data-status="' + $rs + '">' + $secHead + '<div class="card-body">' + $body + '</div></details>')
    }

    $failHtml = ''
    foreach ($r in $reports) {
        foreach ($f in @($r.Flows)) {
            if ($f.Status -eq 'FAILED') {
                $failHtml += '<li><strong>' + (Esc $f.Name) + '</strong> <span class="text-muted">in ' + (Esc $r.FileName) + '</span></li>'
            }
        }
    }
    if ($failHtml -eq '') { $failHtml = '<p class="text-success mb-0">No failed flows.</p>' }
    else { $failHtml = '<ul class="mb-0">' + $failHtml + '</ul>' }

    $template = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@@TITLE@@</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
<style>
  details > summary { list-style: none; }
  details > summary::-webkit-details-marker { display: none; }
  .tile { min-height: 130px; display: flex; flex-direction: column; justify-content: center; align-items: center; }
</style>
</head>
<body class="bg-light">
<div class="container py-4">
  <h1 class="mb-4">@@TITLE@@</h1>
  <div class="row row-cols-2 row-cols-md-6 g-3 mb-4">
    <div class="col"><div class="card h-100 text-center"><div class="card-body tile"><h6 class="text-muted">Reports</h6><h2>@@REPORTS@@</h2><small class="text-muted">&nbsp;</small></div></div></div>
    <div class="col"><div class="card h-100 text-center"><div class="card-body tile"><h6 class="text-muted">Single-flow reports</h6><h2>@@SINGLE@@</h2><small class="text-muted">&nbsp;</small></div></div></div>
    <div class="col"><div class="card h-100 text-center"><div class="card-body tile"><h6 class="text-muted">Multi-flow reports</h6><h2>@@MULTI@@</h2><small class="text-muted">&nbsp;</small></div></div></div>
    <div class="col"><div class="card h-100 text-center"><div class="card-body tile"><h6 class="text-muted">Total flows</h6><h2>@@TOTAL@@</h2><small class="text-muted">&nbsp;</small></div></div></div>
    <div class="col"><div class="card h-100 text-center text-white bg-success"><div class="card-body tile"><h6>Passed flows</h6><h2>@@PASSED@@</h2><small>pass rate @@PASSRATE@@%</small></div></div></div>
    <div class="col"><div class="card h-100 text-center text-white bg-danger"><div class="card-body tile"><h6>Failed flows</h6><h2>@@FAILED@@</h2><small>fail rate @@FAILRATE@@%</small></div></div></div>
  </div>
  <div class="card mb-4"><div class="card-header"><strong>Failed Flows</strong></div>
    <div class="card-body">@@FAILEDLIST@@</div></div>
  <div class="card mb-4">
    <div class="card-header d-flex flex-wrap justify-content-between align-items-center gap-2">
      <strong>Reports</strong>
      <div class="d-flex flex-wrap gap-2">
        <div class="btn-group btn-group-sm">
          <button class="btn btn-outline-secondary" onclick="setF('st','ALL')">All</button>
          <button class="btn btn-outline-success" onclick="setF('st','PASSED')">Passed</button>
          <button class="btn btn-outline-danger" onclick="setF('st','FAILED')">Failed</button>
        </div>
        <div class="btn-group btn-group-sm">
          <button class="btn btn-outline-secondary" onclick="setF('ty','ALL')">All types</button>
          <button class="btn btn-outline-info" onclick="setF('ty','single')">Single flow</button>
          <button class="btn btn-outline-primary" onclick="setF('ty','multi')">Multiple flows</button>
        </div>
      </div>
    </div>
    <div class="table-responsive">
      <table class="table table-hover mb-0">
        <thead><tr><th>#</th><th>Report file</th><th>Type</th><th>Flows</th><th>Passed</th><th>Failed</th><th>Result</th></tr></thead>
        <tbody>@@REPROWS@@</tbody>
      </table>
    </div>
  </div>
  <h4 class="mb-3">Report details (click a report to expand its flows)</h4>
  @@SECTIONS@@
</div>
<script>
var F = {st: 'ALL', ty: 'ALL'};
function setF(k, v) {
  F[k] = v;
  document.querySelectorAll('.rep-row, .rep-section').forEach(function (el) {
    var okS = F.st === 'ALL' || el.dataset.status === F.st;
    var okT = F.ty === 'ALL' || el.dataset.type === F.ty;
    el.style.display = (okS && okT) ? '' : 'none';
  });
}
</script>
</body>
</html>
'@

    $page = $template.Replace('@@TITLE@@', (Esc $title))
    $page = $page.Replace('@@REPORTS@@', [string]$reports.Count)
    $page = $page.Replace('@@SINGLE@@', [string]$singleCount).Replace('@@MULTI@@', [string]$multiCount)
    $page = $page.Replace('@@TOTAL@@', [string]$totalFlows)
    $page = $page.Replace('@@PASSED@@', [string]$passedFlows).Replace('@@FAILED@@', [string]$failedFlows)
    $page = $page.Replace('@@PASSRATE@@', $passRate).Replace('@@FAILRATE@@', $failRate)
    $page = $page.Replace('@@FAILEDLIST@@', $failHtml)
    $page = $page.Replace('@@REPROWS@@', $repRows.ToString())
    $page = $page.Replace('@@SECTIONS@@', $sections.ToString())
    return $page
}

function Parse-Selection([string]$text, [int]$n) {
    $t = $text.Trim().ToLower()
    if ($t -eq 'all' -or $t -eq 'a') { return @(1..$n) }
    $set = New-Object System.Collections.Generic.SortedSet[int]
    foreach ($part in ($t -split ',')) {
        $p = $part.Trim()
        if ($p -eq '') { continue }
        if ($p -match '^(\d+)\s*-\s*(\d+)$') {
            $a = [int]$matches[1]; $b = [int]$matches[2]
            if ($a -lt 1 -or $b -gt $n -or $a -gt $b) { throw "range $p is out of bounds (1-$n)" }
            for ($x = $a; $x -le $b; $x++) { [void]$set.Add($x) }
        } elseif ($p -match '^\d+$') {
            $k = [int]$p
            if ($k -lt 1 -or $k -gt $n) { throw "number $p is out of bounds (1-$n)" }
            [void]$set.Add($k)
        } else {
            throw "cannot read '$p'"
        }
    }
    if ($set.Count -eq 0) { throw 'nothing selected' }
    return @($set)
}

function Main {
    if (-not (Test-Path $reportsDir)) {
        Write-Host "Reports folder not found: $reportsDir" -ForegroundColor Red
        return
    }

    $files = @(Get-ChildItem -Path $reportsDir -Recurse -File |
        Where-Object { $_.Extension -match '^\.html?$' } | Sort-Object Name)
    if ($files.Count -eq 0) {
        Write-Host "No HTML reports found in $reportsDir" -ForegroundColor Red
        return
    }

    $cache = @{}
    Write-Host ""
    Write-Host "Reports in: $reportsDir"
    Write-Host ""
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f = $files[$i]
        try {
            $flows = @(Parse-Report $f.FullName)
        } catch {
            $flows = @()
            Write-Host "  could not read $($f.Name): $($_.Exception.Message)" -ForegroundColor Yellow
        }
        $cache[$i + 1] = $flows
        $n  = $flows.Count
        $nf = @($flows | Where-Object { $_.Status -eq 'FAILED' }).Count
        $tag = 'NO FLOWS'; $color = 'Yellow'
        if ($nf -gt 0) { $tag = 'FAILED'; $color = 'Red' }
        elseif ($n -gt 0) { $tag = 'PASSED'; $color = 'Green' }
        $kind = if ($n -eq 1) { '1 flow' } else { "$n flows" }
        Write-Host ("{0,3}. {1,-58} {2,-9} [{3}]" -f ($i + 1), $f.Name, $kind, $tag) -ForegroundColor $color
    }

    while ($true) {
        Write-Host ""
        Write-Host "Examples:  all   |   1-5   |   2,7,10   |   1-5,8,20"
        $choice = Read-Host "Select reports (or q to quit)"
        if ($choice -match '^(q|quit|exit)$') { break }

        try {
            $idx = Parse-Selection $choice $files.Count
        } catch {
            Write-Host "Invalid selection: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        $reports = @()
        foreach ($i in $idx) {
            $reports += [pscustomobject]@{ FileName = $files[$i - 1].Name; Flows = @($cache[$i]) }
        }

        $totalFlows = 0
        foreach ($r in $reports) { $totalFlows += @($r.Flows).Count }
        if ($totalFlows -eq 0) {
            Write-Host "The selected reports have no flows." -ForegroundColor Yellow
            continue
        }

        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
        $isAll = ($idx.Count -eq $files.Count)

        # Turn the chosen numbers into ranges, e.g. 1,2,3,4,5,7,8 -> "1-5", "7-8"
        $ranges = @()
        $sorted = @($idx | Sort-Object)
        $start = $sorted[0]; $prev = $sorted[0]
        foreach ($v in ($sorted | Select-Object -Skip 1)) {
            if ($v -eq $prev + 1) { $prev = $v; continue }
            $ranges += $(if ($start -eq $prev) { "$start" } else { "$start-$prev" })
            $start = $v; $prev = $v
        }
        $ranges += $(if ($start -eq $prev) { "$start" } else { "$start-$prev" })
        $rangeText = $ranges -join ', '

        if ($isAll) {
            $outPath = Join-Path $outDir ("Full_Flow_Summary_{0}.html" -f $stamp)
            $title = "Full Flow Summary"
        } else {
            $fileRange = $ranges -join '_'
            $outPath = Join-Path $outDir ("Flow_Summary_Reports_{0}_{1}.html" -f $fileRange, $stamp)
            $title = "Flow Summary: Reports $rangeText"
        }

        $html = Build-Page $reports $title
        [IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding($false)))

        $single = @($reports | Where-Object { @($_.Flows).Count -eq 1 }).Count
        $multi  = @($reports | Where-Object { @($_.Flows).Count -gt 1 }).Count
        $passed = 0; $failed = 0
        foreach ($r in $reports) {
            foreach ($fl in @($r.Flows)) {
                if ($fl.Status -eq 'PASSED') { $passed++ }
                elseif ($fl.Status -eq 'FAILED') { $failed++ }
            }
        }
        Write-Host ""
        Write-Host "Created: $outPath" -ForegroundColor Cyan
        Write-Host "Reports: $($reports.Count) (single: $single, multiple: $multi) | Flows: $totalFlows | Passed: $passed | Failed: $failed"
    }
}

Main