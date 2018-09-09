# frozen_string_literal: true

# Code by MSP-Greg

module PreBuild

  if ARGV.length == 0
    ARCH = '64'
  elsif ARGV[0] == '32' || ARGV[0] == '64'
    ARCH = ARGV[0]
  else
    puts "Incorrect first argument, must be nil, '32' or '64'"
    exit 1
  end

class << self

  def run
    revision
  end

  private

  def revision
    Dir.chdir( File.join(__dir__, 'ruby') ) { |d|
      branch = `git branch`[/^\* (.+)/, 1].sub(')', '')[/[^ \/]+\Z/]
      # set branch to trunk if it's a commit
      branch = "trunk" if /\A[0-9a-f]{7}\Z/ =~ branch

      # Get svn from commit info, write to revision.h
      if svn = (`git log -1`)[/svn\+ssh:\S+?@(\d+)/, 1]
        File.open('revision.h', 'wb:utf-8') { |f|
          f.write "#define RUBY_REVISION #{svn}\n" \
                  "#define RUBY_BRANCH_NAME \"#{branch}\"\n"
        }
      end

      # open version.h and get ruby info
      File.open('version.h', 'rb:utf-8') { |f|
        v_data = f.read
        version = v_data[/^#define[ \t]+RUBY_VERSION[ \t]+["']([\d\.]+)["']/, 1]
        patch   = v_data[/^#define[ \t]+RUBY_PATCHLEVEL[ \t]+(-?\d+)/, 1]

        date    = v_data[/^#define[ \t]+RUBY_RELEASE_YEAR[ \t]+(\d{4})/, 1] + '-' +
                  v_data[/^#define[ \t]+RUBY_RELEASE_MONTH[ \t]+(\d{1,2})/, 1].rjust(2,'0') + '-' +
                  v_data[/^#define[ \t]+RUBY_RELEASE_DAY[ \t]+(\d{1,2})/, 1].rjust(2,'0')
        patch = patch == '-1' ? 'dev' : "p#{patch}"
        vers_abi = version.sub(/\d+$/, '0')

        # Add title to Appveyor build
        arch = ARCH == '64' ? '[x64-mingw32]' : '[i386-mingw32]'
        title = "ruby #{version}#{patch} (#{date} #{branch} #{svn}) #{arch}"
        if ENV['APPVEYOR']
          `appveyor UpdateBuild -Message \"#{title}\"`
        end
        puts title
      }
    }
  end

  # Reads patch dir, applies patches
  def apply_patches
    Dir.chdir(File.join(__dir__, 'ruby')) { |dir|
      # collect patches and apply
      patches = Dir["#{__dir__}/patches/{[^_],#{ARCH}/[^_]}*.patch"]
      patches.sort_by! { |p| File.basename(p) }
      patches.each { |p|
        puts "#{YELLOW}#{'—' * 55} #{File.basename(p)}#{RESET}"
        puts `patch -p1 -N --no-backup-if-mismatch -i #{p}`
      }
      puts ''  # just for formatting of prepare.log
    }
  end

end
end
PreBuild.run
