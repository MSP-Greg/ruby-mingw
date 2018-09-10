<# Code by MSP-Greg
Script for building & installing MinGW Ruby for CI
Assumes a Ruby exe is in path
Assumes 'Git for Windows' is installed at $env:ProgramFiles\Git
Assumes '7z             ' is installed at $env:ProgramFiles\7-Zip
For local use, set items in local.ps1
#>

#————————————————————————————————————————————————————————————————— Apply-Patches
# Applies patches
function Apply-Patches {
  Push-Location "$d_repo/patches"
  [string[]]$patches = Get-ChildItem -Include *.patch -Path . -Recurse |
    select -expand name
  Pop-Location
  Push-Location "$d_ruby"
  foreach ($p in $patches) {
    if ($p.substring(0,2) -eq "__") { continue }
    Write-Host $($dash * 55) $p -ForegroundColor $fc
    patch.exe -p1 -N --no-backup-if-mismatch -i "$d_repo/patches/$p"
  }
  Pop-Location
}

#———————————————————————————————————————————————————————————————————— Basic Info
function Basic-Info {
  $env:path = "$d_install/bin;$base_path"
  Write-Host $($dash * 80) -ForegroundColor $fc
  ruby -v
  bundler version
  ruby -ropenssl -e "puts OpenSSL::OPENSSL_LIBRARY_VERSION"
  Write-Host "gem --version" $(gem --version)
  rake -V
  Write-Host "$($dash * 80)`n" -ForegroundColor $fc
}

#———————————————————————————————————————————————————————————————————— Check-Exit
# checks whether to exit
function Check-Exit($msg, $pop) {
  if ($LastExitCode -and $LastExitCode -ne 0) {
    if ($pop) { Pop-Location }
    Write-Line "Failed - $msg" -ForegroundColor $fc
    exit 1
  }
}

#———————————————————————————————————————————————————————————————— Create-Folders
# Creates build, install, log, and git folders at same place as ruby repo folder
function Create-Folders {
  # reset to read/write
  (Get-Item $d_repo).Attributes = 'Normal'
  Get-ChildItem -Directory | foreach {$_.Attributes = 'Normal'}

  # create (or clean) build & install
  if (Test-Path -Path ./build    -PathType Container ) {
    Remove-Item -Path ./build    -recurse
  } New-Item    -Path ./build    -ItemType Directory 1> $null

  if (Test-Path -Path ./$install -PathType Container ) {
    Remove-Item -Path ./$install -recurse
  } New-Item    -Path ./$install -ItemType Directory 1> $null

  if (Test-Path -Path ./logs     -PathType Container ) {
    Remove-Item -Path ./logs     -recurse
  } New-Item    -Path ./logs     -ItemType Directory 1> $null

  # create git symlink, which RubyGems seems to want
  if (!(Test-Path -Path ./git -PathType Container )) {
        New-Item  -Path ./git -ItemType SymbolicLink -Value $d_git 1> $null
  }
  Get-ChildItem -Directory | foreach {$_.Attributes = 'Normal'}
}

#——————————————————————————————————————————————————————————————————————————— Run
# Run a command and check for error
function Run($exec) {
  Write-Line $exec
  iex $exec
  Check-Exit $exec
}

#————————————————————————————————————————————————————————————————————————— Strip
# Strips dll & so files in build folder
function Strip {
  [string[]]$dlls = Get-ChildItem -Include *.dll -Path $d_build -Recurse |
    select -expand fullname
  foreach ($dll in $dlls) { strip.exe --strip-unneeded -p $dll }

  [string[]]$exes = Get-ChildItem -Include *.exe -Path $d_build -Recurse |
    select -expand fullname
  foreach ($exe in $exes) { strip.exe --strip-unneeded -p $exe }

  $so_dir = if ($bits -eq 64) { "$d_build/.ext/x64-mingw32"  }
                         else { "$d_build/.ext/i386-mingw32" }

  [string[]]$sos = Get-ChildItem -Include *.so -Path $so_dir -Recurse |
    select -expand fullname
  foreach ($so in $sos) { strip.exe --strip-unneeded -p $so }
  $msg = "Stripped $($dlls.length) dll files, $($exes.length) exe files, " +
              "and $($sos.length) so files"
  Write-Host $msg -ForegroundColor $fc
}

#————————————————————————————————————————————————————————————————— Set-Variables
# set base variables, including MSYS2 location and bit related varis
function Set-Variables-Local {
  if ($bits -eq 32) {
         $script:march = "i686"   ; $script:carch = "i686"   }
  else { $script:march = "x86-64" ; $script:carch = "x86_64" }

  $script:ruby_path = $(ruby -e "puts RbConfig::CONFIG['bindir']").trim().replace('\', '/')

  $script:chost   = "$carch-w64-mingw32"

  $script:jobs    = $env:NUMBER_OF_PROCESSORS
  $script:fc      = "Yellow"
  $script:dash    = "$([char]0x2015)"
  $script:dl      = $($dash * 80)
}

#——————————————————————————————————————————————————————————————————————— Set-Env
# Set ENV, including gcc flags
function Set-Env {
  $env:path = "$ruby_path;$d_mingw/bin;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"

  $env:D_MSYS2  = $d_msys2
  $env:CFLAGS   = "-march=$march -mtune=generic -O3 -pipe"
  $env:CXXFLAGS = "-march=$march -mtune=generic -O3 -pipe"
  $env:CPPFLAGS = "-D_FORTIFY_SOURCE=2 -D__USE_MINGW_ANSI_STDIO=1 -DFD_SETSIZE=2048"
  $env:LDFLAGS  = "-pipe"
  # not sure if below are needed, maybe jst for makepkg scripts.  See
  # https://github.com/Alexpux/MSYS2-packages/blob/master/pacman/makepkg_mingw64.conf
  # https://github.com/Alexpux/MSYS2-packages/blob/master/pacman/makepkg_mingw32.conf
  $env:CARCH        = $carch
  $env:CHOST        = $chost
  $env:MINGW_CHOST  = $chost
  $env:MINGW_PREFIX = "/$mingw"
}

#——————————————————————————————————————————————————————————————————— start build
# defaults to 64 bit
$script:bits = if ($args.length -eq 1 -and $args[0] -eq 32) { 32 } else { 64 }

cd $PSScriptRoot

. ./0_common.ps1
Set-Variables
Set-Variables-Local
Set-Env


Apply-Patches

Create-Folders

cd $d_repo
ruby 1_1_pre_build.rb 64

cd $d_ruby
Run "sh -c `"autoreconf -fi`""

cd $d_build

$config_args = "--build=$chost --host=$chost --target=$chost --with-out-ext=pty,syslog"

Run "sh -c `"../ruby/configure --disable-install-doc --prefix=/$install $config_args`""
Run "$make -j$jobs up"
Run "$make -j$jobs"
Strip
Run "$make -f GNUMakefile DESTDIR=$d_repo_u install-nodoc"

cd $d_repo

ruby 1_2_post_install.rb $bits $install

$env:path = "$d_install/bin;$d_mingw/bin;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"

ruby 1_3_post_install.rb $bits $install

Basic-Info

Push-Location $d_build/ext
$build_files = "$d_zips/ext_build_files.7z"
&$7z a $build_files **/Makefile **/*.h **/*.log **/*.mk 1> $null
if ($is_av) { Push-AppveyorArtifact $build_files }
Pop-Location
