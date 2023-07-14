# frozen_string_literal: true
require_relative 'lib/ffi/uctags/directory'
src = File.join(FFI::UCtags::EXE_ROOT, 'src')

steps = {
  File.join(src, 'configure') => %w[./autogen.sh],
  File.join(src, 'Makefile')  => %W[./configure
    --prefix=#{FFI::UCtags::EXE_ROOT}
    --disable-readcmd
    --disable-xml
    --disable-json
    --disable-seccomp
    --disable-yaml
    --disable-pcre2
    --without-included-regex
  ],
  FFI::UCtags::EXE_PATH =>
    "#{ENV.fetch('MAKE') do
      require 'etc'
      "make -j #{Etc.nprocessors.ceildiv 2}"
    end} install"
}

steps.each do|filepath, command|
  file(filepath) { sh(*command, chdir: src) }
end
steps.each_key.each_cons(2) {|dependency, name| file name => dependency }

desc '`configure` and `make` the u-ctags submodule'
task default: [FFI::UCtags::EXE_PATH]

desc 'Reap the u-ctags sources and `bundle install`'
task :bundle do
  if File.exist? '.git' # Git/Hub repository
    sh 'git submodule deinit --force u-ctags'
  else # Downloaded directly
    puts "Clearing directory '#{src}'"
    File.delete *Dir[File.join src, '**']
    # Don’t delete the directory itself to match `deinit` behavior
  end
  sh 'bundle install'
end

desc 'same as `rake default bundle`'
task setup: %i[default bundle]
