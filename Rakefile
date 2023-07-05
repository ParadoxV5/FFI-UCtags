# frozen_string_literal: true
require_relative 'lib/ffi/uctags/directory'

src = File.join(FFI::UCtags::EXE_ROOT, 'src')
steps = {
  File.join(src, 'configure')    => %w[./autogen.sh],
  File.join(src, 'Makefile')     => %W[./configure
    --prefix=#{FFI::UCtags::EXE_ROOT}
    --disable-readcmd
    --disable-xml
    --disable-json
    --disable-seccomp
    --disable-yaml
    --disable-pcre2
    --without-included-regex
  ],
  FFI::UCtags::EXE_PATH => %w[make install]
}

steps.each do|filepath, command|
  file(filepath) { system(*command, chdir: src, exception: true) }
end
steps.each_key.each_cons(2) {|dependency, name| file name => dependency }

desc 'configure and make u-ctags'
task default: [FFI::UCtags::EXE_PATH]
