# l10n 棘轮扫描：阻止"硬编码 CJK 字符串"债务继续增长。
#
# 统计 lib/ 下每个 .dart 文件中包含 CJK 字符的字符串字面量数量，
# 与 tool/l10n_baseline.txt 中的基线比较：
#   - 超出基线（含未登记的新文件）→ 退出码 1（CI 失败）
#   - 低于基线 → 通过，并提示可收缩基线（ratchet）
#
# 用法：
#   pwsh tool/l10n_scan.ps1             # 校验模式（CI）
#   pwsh tool/l10n_scan.ps1 -Update     # 重新生成基线（迁移完成后本地收缩）
[CmdletBinding()]
param(
    [switch]$Update
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$libDir = Join-Path $root 'lib'
$baselinePath = Join-Path $PSScriptRoot 'l10n_baseline.txt'

# 近似 Dart 字符串字面量：'...' 或 "..."（含 r'...' 原始串），不跨行。
# 转义引号会提前截断——对"计数棘轮"而言只需确定性，无需精确解析。
$literalRe = [regex]'(?:r)?([''"])(?:(?!\1).)*\1'
$cjkRe = [regex]'[\u4e00-\u9fff]'

# 生成物不参与统计
$excludeParts = @('core/l10n/')
$excludeSuffixes = @('.g.dart', '_mocks.dart')

function Convert-ToRelPosix([string]$path) {
    $rel = $path.Substring($root.Length + 1)
    return ($rel -replace '\\', '/')
}

function Get-ScanCounts {
    $counts = @{}
    foreach ($f in Get-ChildItem -Path $libDir -Recurse -Filter *.dart |
        Sort-Object -Property FullName) {
        $rel = Convert-ToRelPosix $f.FullName
        $skip = $false
        foreach ($p in $excludeParts) { if ($rel.Contains($p)) { $skip = $true } }
        foreach ($s in $excludeSuffixes) { if ($rel.EndsWith($s)) { $skip = $true } }
        if ($skip) { continue }

        # 显式 UTF-8：PS5.1 默认按 ANSI 读，会把中文源码读花
        $text = [System.IO.File]::ReadAllText(
            $f.FullName, [System.Text.UTF8Encoding]::new($false))
        $n = 0
        foreach ($m in $literalRe.Matches($text)) {
            if ($cjkRe.IsMatch($m.Value)) { $n++ }
        }
        if ($n -gt 0) { $counts[$rel] = $n }
    }
    return $counts
}

function Read-Baseline {
    $out = @{}
    if (-not (Test-Path -LiteralPath $baselinePath)) { return $out }
    foreach ($line in [System.IO.File]::ReadAllLines(
        $baselinePath, [System.Text.UTF8Encoding]::new($false))) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $idx = $t.LastIndexOf(' ')
        if ($idx -gt 0) {
            $file = $t.Substring(0, $idx)
            $cnt = 0
            if ([int]::TryParse($t.Substring($idx + 1), [ref]$cnt)) {
                $out[$file] = $cnt
            }
        }
    }
    return $out
}

function Write-Baseline($counts) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# l10n 棘轮基线：每行 <相对路径> <CJK 字面量数>')
    $lines.Add('# 迁移完一个文件后运行 pwsh tool/l10n_scan.ps1 -Update 收缩基线')
    $keys = @($counts.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    foreach ($k in $keys) { $lines.Add("$k $($counts[$k])") }
    # 无 BOM UTF-8（跨 PS5/pwsh7 一致）
    [System.IO.File]::WriteAllLines(
        $baselinePath, $lines, [System.Text.UTF8Encoding]::new($false))
}

$counts = Get-ScanCounts

if ($Update) {
    Write-Baseline $counts
    $total = ($counts.Values | Measure-Object -Sum).Sum
    if ($null -eq $total) { $total = 0 }
    Write-Output "baseline updated: $($counts.Count) files, $total CJK literals"
    exit 0
}

$base = Read-Baseline
$fail = $false
$keys = @($counts.Keys)
[Array]::Sort($keys, [StringComparer]::Ordinal)
foreach ($f in $keys) {
    $c = $counts[$f]
    if (-not $base.ContainsKey($f)) {
        Write-Output "NEW-DEBT  $f  $c 处（基线未登记，请迁移到 arb 或有意更新基线）"
        $fail = $true
    } elseif ($c -gt $base[$f]) {
        Write-Output "OVER      $f  $c > $($base[$f])"
        $fail = $true
    }
}
$bkeys = @($base.Keys)
[Array]::Sort($bkeys, [StringComparer]::Ordinal)
foreach ($f in $bkeys) {
    $cur = if ($counts.ContainsKey($f)) { $counts[$f] } else { 0 }
    if ($cur -lt $base[$f]) {
        Write-Output "SHRINK?   $f  $cur < $($base[$f])（可运行 -Update 收缩基线）"
    }
}

$total = ($counts.Values | Measure-Object -Sum).Sum
if ($null -eq $total) { $total = 0 }
$btotal = ($base.Values | Measure-Object -Sum).Sum
if ($null -eq $btotal) { $btotal = 0 }
if ($fail) {
    Write-Output "FAIL: 发现新增硬编码 CJK 字符串（当前共 $total 处）"
    exit 1
}
Write-Output "OK: 未新增 l10n 债务（当前共 $total 处，基线 $btotal 处）"
exit 0
