<# Code by MSP-Greg
Runs Ruby tests with STDOUT & STDERR sent to two files, allows setting a max
time, so if a test freezes, it can be stopped.
#>

#————————————————————————————————————————————————————————————————————— Kill-Proc
# Kills a process by first looping thru child & grandchild processes and
# stopping them, then stops passed process
function Kill-Proc($proc) {
  $processes = @()
  $p_pid = $proc.id
  $temp = $(Get-CimInstance -ClassName Win32_Process | where {$_.ProcessId -eq $p_pid} )

  $parents = @($temp)

  while ($parents -and $parents.length -gt 0) {
    $processes += $parents
    $children = @()
    foreach ($parent in $parents) {
      [int32]$p_pid = $parent.ProcessId
      $children += $(Get-CimInstance -ClassName Win32_Process |
        where {$_.ParentProcessId -eq $p_pid} )
    }
    $parents = $children
  }
  $t = -1 * ($processes.length)
  $r_processes = $processes[-1..$t]

  Write-Host "Process           pid   parent" -ForegroundColor $fc
  foreach ($process in $r_processes) {
    $t = "{0,-14}  {1,5}    {2,5}" -f @($process.Name, $process.ProcessId, $process.ParentProcessId)
    Write-Host $t
  }
  foreach ($process in $r_processes) {
    $id = $process.ProcessId
    if (!$process.HasExited) {
      Stop-Process -Id $id -Force
      sleep (0.1)
    }
  }
  Write-Host "Processes Killed!" -ForegroundColor $fc
}

#—————————————————————————————————————————————————————————————————————— Run-Proc
# Runs a process with a timeout setting, sets STDOUT & STDERR to files
# Outputs running dots to console
function Run-Proc {
  Param( [string]$StdOut , [string]$exe    , [string]$Title ,
         [string]$StdErr , [string]$e_args , [string]$Dir   , [int]$TimeLimit
  )

  Write-Host "$($dash * 50) $Title" -ForegroundColor $fc

  if ($TimeLimit -eq $null -or $TimeLimit -eq 0 ) {
    Write-Host "Need TimeLimit!"
    exit
  }

  $msg = "Time Limit {0,8:n2} seconds  {1}" -f @($TimeLimit, $(Get-Date -Format mm:ss))
  Write-Host $msg

  $start = Get-Date

  $proc = Start-Process $exe -ArgumentList $e_args `
    -RedirectStandardOutput $d_logs/$StdOut `
    -RedirectStandardError  $d_logs/$StdErr `
    -WorkingDirectory $Dir `
    -NoNewWindow -PassThru

  Wait-Process -Id $proc.id -Timeout $TimeLimit -ea 0 -ev froze
  if ($froze) {
    Write-Host "Exceeded time limit..." -ForegroundColor $fc
    Kill-Proc $proc
  } else {
    $diff = New-TimeSpan -Start $start -End $(Get-Date)
    $msg = "Total Time {0,8:n2}" -f @($diff.TotalSeconds)
    Write-Host $msg
  }
}

#————————————————————————————————————————————————————————————————————— BasicTest
function BasicTest {
  # needs miniruby at root (build)
  $env:RUBY = $ruby_exe
  Run-Proc `
    -exe    "ruby.exe" `
    -e_args "-rdevkit --disable-gems ../ruby/basictest/runner.rb" `
    -StdOut "test_basic.log" `
    -StdErr "test_basic_err.log" `
    -Title  "test-basic" `
    -Dir    $d_build `
    -TimeLimit 20
}

#————————————————————————————————————————————————————————————————— BootStrapTest
function BootStrapTest {
  Run-Proc `
    -exe    $ruby_exe `
    -e_args "--disable=gems runner.rb --ruby=`"$ruby_exe --disable=gems`" -v" `
    -StdOut "test_bootstrap.log" `
    -StdErr "test_bootstrap_err.log" `
    -Title  "btest" `
    -Dir    "$d_ruby/bootstraptest" `
    -TimeLimit 100
}

#—————————————————————————————————————————————————————————————————————— Test-All
function Test-All {
  # Standard Ruby CI doesn't run this test, remove for better comparison
  # $remove_test = "$d_ruby/test/ruby/enc/test_case_comprehensive.rb"
  # if (Test-Path -Path $remove_test -PathType Leaf) { Remove-Item -Path $remove_test }

  $env:RUBY_FORCE_TEST_JIT = '1'

  $ta_ruby = "-I../ruby/lib -I. -I.ext/common  ../ruby/tool/runruby.rb" ` +
             " --extout=.ext -- --disable=gems"

  $args = "$ta_ruby ../ruby/test/runner.rb" + `
        " --ruby=`"./miniruby.exe $ta_ruby`"" + `
        " --excludes-dir=../ruby/test/excludes --name=!/memory_leak/ -j $jobs -a" + `
        " --retry --job-status=normal --show-skip --subprocess-timeout-scale=1.5"

  Run-Proc `
    -exe    "$d_build/miniruby.exe" `
    -e_args $args `
    -StdOut "test_all.log" `
    -StdErr "test_all_err.log" `
    -Title  "test-all" `
    -Dir    $d_build `
    -TimeLimit 1600
}

#—————————————————————————————————————————————————————————————————————————— Spec
function Spec {

  (Get-Item $d_build).Attributes = 'Normal'

  $incl = "-I./.ext/$rarch -I./.ext/common -I$d_ruby/lib"

  $args = "$incl --disable=gems -r./$rarch-fake" + `
    " $d_ruby/spec/mspec/bin/mspec run -B $d_ruby/spec/default.mspec -j $incl"

  $env:SRCDIR = $d_ruby

  Run-Proc `
    -exe    "$d_build/ruby.exe" `
    -e_args $args `
    -StdOut "test_spec.log" `
    -StdErr "test_spec_err.log" `
    -Title  "test-spec" `
    -Dir    $d_build `
    -TimeLimit 250
}

#————————————————————————————————————————————————————————————————————————— MSpec
function MSpec {

  Run-Proc `
    -exe    "ruby.exe" `
    -e_args "--disable=gems ../mspec/bin/mspec -j -rdevkit -T `"--disable=gems`"" `
    -StdOut "test_mspec.log" `
    -StdErr "test_mspec_err.log" `
    -Title  "test-mspec" `
    -Dir    "$d_ruby/spec/ruby" `
    -TimeLimit 250
}

#————————————————————————————————————————————————————————————————————————— setup
# defaults to 64 bit
$script:bits = if ($args.length -eq 1 -and $args[0] -eq 32) { 32 } else { 64 }

cd $PSScriptRoot
. ./0_common.ps1
Set-Variables
$ruby_exe = "$d_install/bin/ruby.exe"

#————————————————————————————————————————————————————————————————— start testing
# Set path to only include ruby install folder
$env:path = "$d_install/bin;$d_msys2/usr/bin;$base_path"

BasicTest
BootStrapTest

# No Ruby
$env:path = "$d_mingw;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"
Test-All

# Same as Test-All, just for good measure
$env:path = "$d_mingw;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"
Spec

# Remove MSYS2 folders, as devkit should enable them
$env:path = "$d_install/bin;$d_repo/git/cmd$base_path"
MSpec

#—————————————————————————————————————————————————— cleanup, save artifacts, etc

# remove zero length log files, typically stderr files
$zero_length_files = Get-ChildItem -Path $d_logs -Include *.log -Recurse |
  where {$_.length -eq 0}
foreach ($file in $zero_length_files) { Remove-Item -Path $file -Force }

$env:path = "$d_install/bin;$d_repo/git/cmd;$base_path"

# seems to be needed for proper dash encoding in 2_1_test_script.rb
[Console]::OutputEncoding = New-Object -typename System.Text.UTF8Encoding

# used in 2_1_test_script.rb
$env:PS_ENC = [Console]::OutputEncoding.HeaderName

cd $d_repo
ruby 2_1_test_script.rb $bits $install
$exit = ($LastExitCode -and $LastExitCode -ne 0)

if ($exit) { exit 1 }
