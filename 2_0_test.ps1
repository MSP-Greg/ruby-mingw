<# Code by MSP-Greg
Runs Ruby tests with STDOUT & STDERR sent to two files, allows setting a max
time, so if a test freezes, it can be stopped.
#>

#————————————————————————————————————————————————————————————————————— Kill-Proc
# Kills a process by first looping thru child & grandchild processes and
# stopping them, then stops passed process
function Kill-Proc($proc) {
  $pid = $proc.id
  While ($1_proc = $(Get-CimInstance -ClassName Win32_Process |
    where {$_.ParentProcessId -eq $pid} )) {
    $1_id = $1_proc.ProcessId
    While ($2_proc = $(Get-CimInstance -ClassName Win32_Process |
      where {$_.ParentProcessId -eq $1_id} )) {
      $2_id = $2_proc.ProcessId
      While ($3_proc = $(Get-CimInstance -ClassName Win32_Process |
        where {$_.ParentProcessId -eq $2_id} )) {
        $3_id = $3_proc.ProcessId
        Write-Host "Stop-Process " + $3_proc.name
        Stop-Process -Id $3_id -Force
      }
      if (Get-Process -pid $2_id -ErrorAction SilentlyContinue) {
         Stop-Process -Id  $2_id -Force
        Write-Host "Stop-Process " + $2_proc.name
      }
    }
    if (Get-Process -pid $1_id -ErrorAction SilentlyContinue) {
       Stop-Process -Id  $1_id -Force
      Write-Host "Stop-Process " + $1_proc.name
    }
  }
  if (Get-Process -pid $pid -ErrorAction SilentlyContinue) {
     Stop-Process -Id  $pid -Force
    Write-Host "Stop-Process " + $proc.name
  }
  $is_running = $false
  Write-Host "`nProcess Killed!" -ForegroundColor $fc
}

#—————————————————————————————————————————————————————————————————————— Run-Proc
# Runs a process with a timeout setting, sets STDOUT & STDERR to files
# Outputs running dots to console
function Run-Proc {
  Param( [string]$StdOut , [string]$exe    , [string]$Title ,
         [string]$StdErr , [string]$e_args , [string]$Dir   , [int]$TimeLimit
  )

  Write-Host "$dl $Title" -ForegroundColor $fc

  if ($TimeLimit -eq $null -or $TimeLimit -eq 0 ) {
    Write-Host "Need TimeLimit!"
    exit
  } else {
    $msg = "Time Limit {0,8:n2} seconds" -f @($TimeLimit)
    Write-Host $msg
  }

  $proc = Start-Process $exe -ArgumentList $e_args `
    -RedirectStandardOutput $d_logs/$StdOut `
    -RedirectStandardError  $d_logs/$StdErr `
    -WorkingDirectory $Dir `
    -NoNewWindow -PassThru

  $timer = [system.diagnostics.stopwatch]::StartNew()
  $ctr = 0
  # 20 => ~400, 1600 => ~4200
  $interval_ms = [int32](([math]::log10($TimeLimit) - 1.101) * 2000)
  $is_running = $true
  Do {
    if ($timer.Elapsed.TotalSeconds -gt $TimeLimit) {
      if ($is_running) { Kill-Proc $proc }
    } else {
      $ctr += 1
      Write-Host '.' -NoNewLine
      if ($ctr % 80 -eq 0) { Write-Host }
    }
    Start-Sleep -Milliseconds $interval_ms
  } Until ( $proc.HasExited )

  $test_fails += if ($LastExitCode) { $LastExitCode } else { 0 }
  $msg = "`nTotal Time {0,8:n2}" -f @($timer.Elapsed.TotalSeconds)
  Write-Host $msg
  $timer.Stop()
  $timer = $null
  $proc  = $null
}

#————————————————————————————————————————————————————————————————— start testing
# defaults to 64 bit
$script:bits = if ($args.length -eq 1 -and $args[0] -eq 32) { 32 } else { 64 }

cd $PSScriptRoot
. ./0_common.ps1
Set-Variables

# Standard Ruby CI doesn't run this test, remove for better comparison
# $remove_test = "$d_ruby/test/ruby/enc/test_case_comprehensive.rb"
# if (Test-Path -Path $remove_test -PathType Leaf) { Remove-Item -Path $remove_test }

$env:GIT  = "$d_repo/git/cmd/git.exe"

# Set path to only include ruby install folder
$env:path = "$d_install/bin;$d_msys2/usr/bin;$base_path"

#————————————————————————————————————————————————————————————————————— basictest
# needs miniruby at root (build)
$env:RUBY = "$d_install/bin/ruby.exe"
Run-Proc `
  -exe    "ruby.exe" `
  -e_args "-rdevkit --disable-gems ../ruby/basictest/runner.rb" `
  -StdOut "test_basic.log" `
  -StdErr "test_basic_err.log" `
  -Title  "test-basic" `
  -Dir    $d_build `
  -TimeLimit 20

#————————————————————————————————————————————————————————————————————— bootstrap
Run-Proc `
  -exe    "ruby.exe" `
  -e_args "--disable-gems runner.rb --ruby=`"$d_install/bin/ruby.exe --disable-gems`" -v" `
  -StdOut "test_bootstrap.log" `
  -StdErr "test_bootstrap_err.log" `
  -Title  "btest" `
  -Dir    "$d_ruby/bootstraptest" `
  -TimeLimit 100

#—————————————————————————————————————————————————————————————————————— test-all
$env:RUBY_FORCE_TEST_JIT = '1'

$env:path = "$d_mingw/bin;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"

$args = "test-all TESTOPTS=`"-j$jobs -a --retry --job-status=normal " + `
        "--show-skip --subprocess-timeout-scale=1.5`""

Run-Proc `
  -exe    $make `
  -e_args $args `
  -StdOut "test_all.log" `
  -StdErr "test_all_err.log" `
  -Title  "test-all" `
  -Dir    $d_build `
  -TimeLimit 1600

#—————————————————————————————————————————————————————————————————————————— spec
$env:path = "$d_mingw/bin;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"
(Get-Item $d_build).Attributes = 'Normal'

Run-Proc `
  -exe    $make `
  -e_args "test-spec `"MSPECOPT=-j`"" `
  -StdOut "test_spec.log" `
  -StdErr "test_spec_err.log" `
  -Title  "test-spec" `
  -Dir    $d_build `
  -TimeLimit 250 `

#————————————————————————————————————————————————————————————————————————— mspec
$env:path = "$d_install/bin;$d_msys2/usr/bin;$d_mingw/bin;$base_path"
(Get-Item $d_ruby/spec     ).Attributes = 'Normal'
(Get-Item $d_ruby/spec/ruby).Attributes = 'Normal'

Run-Proc `
  -exe    "ruby.exe" `
  -e_args "-rdevkit --disable-gems ../mspec/bin/mspec -j" `
  -StdOut "test_mspec.log" `
  -StdErr "test_mspec_err.log" `
  -Title  "test-mspec" `
  -Dir    "$d_ruby/spec/ruby" `
  -TimeLimit 250 `

$zero_length_files = Get-ChildItem -Path $d_logs -Include *.log -Recurse |
  where {$_.length -eq 0}

foreach ($file in $zero_length_files) { Remove-Item -Path $file -Force }

$env:path = "$d_install/bin;$d_repo/git/cmd;$base_path"

# seems to be needed for proper dash encoding
[Console]::OutputEncoding = New-Object -typename System.Text.UTF8Encoding

# used in 2_1_test_script.rb
$env:PS_ENC = [Console]::OutputEncoding.HeaderName

ruby 2_1_test_script.rb
$exit = ($LastExitCode -and $LastExitCode -ne 0)

Write-Host "`n$($dash * 8) Encoding $($dash * 8)" -ForegroundColor $fc
Write-Host "PS Console  $([Console]::OutputEncoding.HeaderName)"
Write-Host "PS Output   $($OutputEncoding.HeaderName)"
iex "ruby.exe -e `"['external','filesystem','internal','locale'].each { |e| puts e.ljust(12) + Encoding.find(e).to_s }`""
Write-Host ''
if ($exit) { exit 1 }
