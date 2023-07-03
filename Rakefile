# frozen_string_literal: true

prefix = 'u-ctags'
src = File.join(prefix, 'src')
steps = {
  File.join(src, 'configure')    => %w[./autogen.sh],
  File.join(src, 'Makefile')     => %W[./configure
    --prefix=#{File.absolute_path prefix}
    --disable-readcmd
    --disable-xml
    --disable-json
    --disable-seccomp
    --disable-yaml
    --disable-pcre2
    --without-included-regex
  ],
  File.join(prefix, 'bin/ctags') => %w[make install]
}

steps.each do|filepath, command|
  file(filepath) { system(*command, chdir: src, exception: true) }
end
steps.each_key.each_cons(2) {|dependency, name| file name => dependency }

desc 'configure and make u-ctags'
task default: [steps.each_key.reverse_each.first]
