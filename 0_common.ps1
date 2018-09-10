<# Code by MSP-Greg
Sets variables used in 1_0_build_install_64.ps1 and 2_0_test.ps1
If running locally, use ./local.ps1
#>

#————————————————————————————————————————————————————————————————— Set-Variables
# set base variables, including MSYS2 location and bit related varis
function Set-Variables {
  if ($env:Appveyor -eq 'True') {
    $script:is_av     = $true
    $script:d_msys2   = "C:/msys64"
    $script:d_git     =  "$env:ProgramFiles/Git"
    $script:7z        =  "$env:ProgramFiles/7-Zip/7z.exe"
    $script:base_path = ("$env:ProgramFiles/7-Zip;" + `
      "$env:ProgramFiles/AppVeyor/BuildAgent;$d_git/cmd;" + `
      "$env:SystemRoot/system32;$env:ProgramFiles;$env:SystemRoot").replace('\', '/')
  } else {
    ./local.ps1
  }

  $script:d_repo   = $PSScriptRoot.replace('\', '/')
  # below is a *nix style path, ie, 'C:\' becomes '/c/'
  $script:d_repo_u = if ($d_repo -cmatch "\A[A-Z]:") {
    $t = $d_repo.replace(':', '')
    $t = '/' + $t.substring(0,1).ToLower() + $t.substring(1, $t.length-1)
    $t
  } else { $d_repo }

  $script:mingw   = "mingw$bits"

  $script:d_build   = "$d_repo/build"
  $script:d_logs    = "$d_repo/logs"
  $script:d_mingw   = "$d_msys2/$mingw"
  $script:d_ruby    = "$d_repo/ruby"
  $script:d_zips    = "$d_repo/zips"

  $script:install   = "install"
  $script:d_install = "$d_repo/$install"

  $script:make = "mingw32-make.exe"
  # $script:make = "make"

  $script:jobs = $env:NUMBER_OF_PROCESSORS
  $script:fc   = "Yellow"
  $script:dash = "$([char]0x2015)"
  $script:dl   = $($dash * 80)

  $env:GIT     = "$d_repo/git/cmd/git.exe"
  $env:MSYS_NO_PATHCONV = '1'
}

#———————————————————————————————————————————————————————————————————— Write-Line
# Write 80 dash line then msg in color $fc
function Write-Line($msg) { Write-Host "$dl`n$msg" -ForegroundColor $fc }
