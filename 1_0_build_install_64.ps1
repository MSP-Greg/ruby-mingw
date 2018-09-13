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
  Write-Host ''
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
# creates build, install, log, and git folders at same place as ruby repo folder
# most of the code is for local builds, as the folders should be cleaned
function Create-Folders {
  # reset to read/write
  (Get-Item $d_repo).Attributes = 'Normal'

  # create (or clean) build & install
  if (Test-Path   -Path ./build    -PathType Container ) {
   (Get-Item $d_build).Attributes = 'Normal'
    Get-ChildItem -Path ./build    -Recurse -Directory -Force |
      foreach {$_.Attributes = 'Normal'}
    Remove-Item   -Path ./build    -Recurse
  }

  if (Test-Path   -Path ./$install -PathType Container ) {
   (Get-Item ./$install).Attributes = 'Normal'
    Get-ChildItem -Path ./$install -Recurse -Directory -Force |
      foreach {$_.Attributes = 'Normal'}
    Remove-Item   -Path ./$install -Recurse
  }

  if (Test-Path   -Path ./logs     -PathType Container ) {
   (Get-Item ./logs).Attributes = 'Normal'
    Get-ChildItem -Path ./logs     -Recurse -Directory -Force |
      foreach {$_.Attributes = 'Normal'}
    Remove-Item   -Path ./logs     -Recurse
  }

  # create git symlink, which RubyGems seems to want
  if (!(Test-Path -Path ./git -PathType Container )) {
        New-Item  -Path ./git -ItemType SymbolicLink -Value $d_git 1> $null
  }

  New-Item      -Path ./build    -ItemType Directory 1> $null
  New-Item      -Path ./$install -ItemType Directory 1> $null
  New-Item      -Path ./logs     -ItemType Directory 1> $null


  Get-ChildItem -Directory | foreach {$_.Attributes = 'Normal'}

}

#——————————————————————————————————————————————————————————————————————————— Run
# Run a command and check for error
function Run($exec, $silent = $false) {
  Write-Line "$exec"
  if ($silent) { iex $exec -ErrorAction SilentlyContinue }
  else         { iex $exec }
  Check-Exit $exec
}

#————————————————————————————————————————————————————————————————————————— Strip
# Strips dll & so files in build folder
function Strip {
  [string[]]$dlls = Get-ChildItem -Include *.dll -Recurse |
    select -expand fullname
  foreach ($dll in $dlls) { strip.exe --strip-unneeded -p $dll }

  [string[]]$exes = Get-ChildItem -Include *.exe -Recurse |
    select -expand fullname
  foreach ($exe in $exes) { strip.exe --strip-all -p $exe }

  $so_dir = "$d_build/.ext/$rarch"

  [string[]]$sos = Get-ChildItem -Include *.so -Path $so_dir -Recurse |
    select -expand fullname
  foreach ($so in $sos) { strip.exe --strip-unneeded -p $so }
  $msg = "Stripped $($dlls.length) dll files, $($exes.length) exe files, " +
              "and $($sos.length) so files"
  Write-Line $msg -ForegroundColor
}

#————————————————————————————————————————————————————————————————— Set-Variables
# set base variables, including MSYS2 location and bit related varis
function Set-Variables-Local {
  $script:ruby_path = $(ruby.exe -e "puts RbConfig::CONFIG['bindir']").trim().replace('\', '/')
}

#——————————————————————————————————————————————————————————————————————— Set-Env
# Set ENV, including gcc flags
function Set-Env {
  $env:path = "$ruby_path;$d_mingw/bin;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"

  # used in Ruby scripts
  $env:D_MSYS2  = $d_msys2

  $env:CFLAGS   = "-march=$march -mtune=generic -O3 -pipe"
  $env:CXXFLAGS = "-march=$march -mtune=generic -O3 -pipe"
  $env:CPPFLAGS = "-D_FORTIFY_SOURCE=2 -D__USE_MINGW_ANSI_STDIO=1 -DFD_SETSIZE=2048"
  $env:LDFLAGS  = "-pipe"
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

Run "$make -j$jobs update-unicode"
Run "$make -j$jobs update-gems"

# below sets some directories to normal in case they're set to read-only
(Get-Item $d_ruby ).Attributes = 'Normal'
Get-ChildItem -Directory -Path  $d_ruby      -Force -Recurse |
  foreach {$_.Attributes = 'Normal'}
Get-ChildItem -Directory -Path "$d_ruby/enc" -Force -Recurse |
  foreach {$_.Attributes = 'Normal'}
(Get-Item $d_build).Attributes = 'Normal'

Run "$make -j$jobs 2>&1" $true

Strip
Run "$make -f GNUMakefile DESTDIR=$d_repo_u install-nodoc"

cd $d_repo

# run with old ruby
ruby 1_2_post_install.rb $bits $install

$env:path = "$d_install/bin;$d_mingw/bin;$d_repo/git/cmd;$d_msys2/usr/bin;$base_path"

# run with new ruby (gem install, exc)
ruby 1_3_post_install.rb $bits $install

Basic-Info

# save extension build files
Push-Location $d_build/ext
$build_files = "$d_zips/ext_build_files.7z"
&$7z a $build_files **/Makefile **/*.h **/*.log **/*.mk 1> $null
if ($is_av) { Push-AppveyorArtifact $build_files -DeploymentName "Ext build files" }
Pop-Location
