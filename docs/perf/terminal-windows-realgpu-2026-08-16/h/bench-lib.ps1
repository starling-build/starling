# Shared pieces for the Windows long round. Dot-sourced by the in-terminal
# runners. Pure ASCII on purpose (see the PowerShell authoring notes).

# --- which process are we measuring? ----------------------------------------
# The runner executes INSIDE the terminal under test, so it has to find that
# terminal by walking up its own ancestry -- the pid does not exist yet when
# the orchestrator builds the command line. Stop at the first ancestor that is
# one of the two terminals by name rather than at "the first non-shell": on
# Windows the chain runs through cmd.exe AND the console host, and a
# generic non-shell test stops at OpenConsole.exe, which is the very process
# whose cost this round exists to attribute separately.
function Find-Terminal {
    $names = @('TerminalApp', 'WindowsTerminal')
    $cur = $PID
    for ($i = 0; $i -lt 12; $i++) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -EA SilentlyContinue
        if (-not $p) { break }
        $parent = $p.ParentProcessId
        if (-not $parent -or $parent -le 4) { break }
        $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$parent" -EA SilentlyContinue
        if (-not $pp) { break }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($pp.Name)
        if ($names -contains $base) { return @{ Pid = $parent; Name = $base } }
        $cur = $parent
    }
    return $null
}

# --- CPU, counting the console host -----------------------------------------
# A Windows terminal does NOT do all its own work: ConPTY's console host
# re-synthesizes the whole stream, and it is a separate process. Ours spawns
# its own bundled OpenConsole.exe; Windows Terminal hosts one too. Measuring
# only the terminal process gave a 3.3x-wrong answer on this box once already
# (the inbox conhost was carrying the cost), so every CPU number here is the
# terminal PLUS its host children.
#
# Returned as a hashtable pid -> seconds so the caller can diff two samples
# and notice a host that came or went between them, rather than silently
# losing its time in a scalar.
function Get-TermCpuMap([int]$TermPid) {
    $map = @{}
    $hosts = @('OpenConsole', 'conhost')
    $ids = New-Object System.Collections.Generic.List[int]
    $ids.Add($TermPid)
    foreach ($c in Get-CimInstance Win32_Process -Filter "ParentProcessId=$TermPid" -EA SilentlyContinue) {
        $b = [System.IO.Path]::GetFileNameWithoutExtension($c.Name)
        if ($hosts -contains $b) {
            $ids.Add([int]$c.ProcessId)
            # one more level: conpty re-parents its host under itself
            foreach ($g in Get-CimInstance Win32_Process -Filter "ParentProcessId=$($c.ProcessId)" -EA SilentlyContinue) {
                $gb = [System.IO.Path]::GetFileNameWithoutExtension($g.Name)
                if ($hosts -contains $gb) { $ids.Add([int]$g.ProcessId) }
            }
        }
    }
    foreach ($id in $ids) {
        $p = Get-Process -Id $id -EA SilentlyContinue
        if ($p) { $map[$id] = $p.TotalProcessorTime.TotalSeconds }
    }
    return $map
}

function Sum-CpuDelta($before, $after) {
    $total = 0.0
    foreach ($k in $after.Keys) {
        $b = if ($before.ContainsKey($k)) { $before[$k] } else { 0.0 }
        $total += ($after[$k] - $b)
    }
    return $total
}

function Get-TermRssKb([int]$TermPid) {
    $p = Get-Process -Id $TermPid -EA SilentlyContinue
    if ($p) { return [int]($p.WorkingSet64 / 1024) }
    return 0
}

# --- writing the corpus at the terminal -------------------------------------
# NOT `cmd /c type`, which every earlier Windows round used. type converts in
# chunks and mangles any UTF-8 sequence that straddles a chunk edge: measured
# on this box, a box-drawing character at byte 4094 became a wide replacement
# glyph, and padding the file past 4096 merely moved the damage to a 512
# boundary. That corrupts 05_unicode -- the one workload whose whole point is
# multi-byte input -- and it does so invisibly, because a replacement glyph
# costs about what the real one does.
#
# This writes raw bytes in 64 KB chunks and BACKS OFF to the last complete
# UTF-8 sequence before each write, so no boundary ever splits a character.
# Same writer for both terminals, so the comparison stays fair; it is simply
# no longer feeding either of them broken input.
function Write-Corpus([string]$Path) {
    $out = [System.Console]::OpenStandardOutput()
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $size = 65536
        $buf = New-Object byte[] ($size + 4)
        $carry = 0
        while ($true) {
            $n = $fs.Read($buf, $carry, $size)
            if ($n -le 0) { break }
            $have = $carry + $n
            # walk back off a trailing partial sequence (continuation bytes are
            # 10xxxxxx; a lead byte tells us how many bytes the sequence needs)
            $cut = $have
            $k = $have - 1
            $scan = 0
            while ($k -ge 0 -and $scan -lt 4) {
                $b = $buf[$k]
                if (($b -band 0xC0) -ne 0x80) {
                    $need = 1
                    if     (($b -band 0x80) -eq 0x00) { $need = 1 }
                    elseif (($b -band 0xE0) -eq 0xC0) { $need = 2 }
                    elseif (($b -band 0xF0) -eq 0xE0) { $need = 3 }
                    elseif (($b -band 0xF8) -eq 0xF0) { $need = 4 }
                    if (($k + $need) -gt $have) { $cut = $k } else { $cut = $have }
                    break
                }
                $k--; $scan++
            }
            $out.Write($buf, 0, $cut)
            $carry = $have - $cut
            if ($carry -gt 0) { [System.Array]::Copy($buf, $cut, $buf, 0, $carry) }
        }
        if ($carry -gt 0) { $out.Write($buf, 0, $carry) }
        $out.Flush()
    } finally {
        $fs.Dispose()
    }
}

# --- is the machine in the same state it was last time? ------------------------
# A fixed integer loop, timed. It touches no I/O and no terminal, so it moves
# only when the machine's compute throughput moves -- power state, thermal
# state, a background hog. Record it in every leg and an anomalous round
# announces itself instead of being discovered days later.
#
# This exists because of the 08-16 round: one WT leg came out 10-36% faster
# than six other runs of the same thing and nothing in the data could say
# why, after the lock screen, leg length, occlusion, cumulative bytes, memory
# and '% Processor Performance' had all been ruled out. That counter reads
# ~79% on this box whether idle or saturated, so it cannot answer the
# question; this can.
function Measure-CpuRef {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $acc = 0
    for ($i = 0; $i -lt 3000000; $i++) { $acc = ($acc + $i) % 1000003 }
    $sw.Stop()
    return $sw.Elapsed.TotalSeconds
}

function Reset-Term {
    $e = [char]27
    Write-Host -NoNewline ("$e[0m$e[r$e[?1049l$e[2J$e[H")
}

function Get-Grid {
    $s = $Host.UI.RawUI.WindowSize
    return "$($s.Height)x$($s.Width)"
}
