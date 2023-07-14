# frozen_string_literal: true


# Building Tasks #

require_relative 'lib/ffi/uctags/directory'
src = File.join(FFI::UCtags::EXE_ROOT, 'src')

steps = {
  File.join(src, 'configure') => './autogen.sh',
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
      "make -j #{Etc.nprocessors/2 + 1}"
    end} install"
}

steps.each do|filepath, command|
  file(filepath) { system(*command, chdir: src, exception: true) }
end
steps.each_key.each_cons(2) {|dependency, name| file name => dependency }

desc '`configure` and `make` the u-ctags submodule'
task default: [FFI::UCtags::EXE_PATH]

desc 'Reap the u-ctags sources and `bundle install`'
task :bundle do
  if File.exist? '.git' # Git/Hub repository
    system 'git submodule deinit --force u-ctags'
  else # Downloaded directly
    puts "Clearing directory '#{src}'"
    File.delete *Dir[File.join src, '**']
    # Don’t delete the directory itself to match `deinit` behavior
  end
  system 'bundle install'
end

desc 'same as `rake default bundle`'
task setup: %i[default bundle]


# Development Tasks #

begin
  require 'minitest/test_task'
  # Create the following tasks:
  # * test          : run tests
  # * test:cmd      : print the testing command
  # * test:isolated : run tests independently to surface order dependencies
  # * test:deps     : (alias of test:isolated)
  # * test:slow     : run tests and reports the slowest 25
  Minitest::TestTask.create 'test', default: false
rescue ArgumentError => e
  raise LoadError, 'Please do `bundle exec rake` for the time being.', cause: e
rescue LoadError
  warn 'Minitest not installed. Testing tasks not available.'
end
