[
  %w[./autogen.sh
  ],
  %W[./configure
    --prefix=#{File.absolute_path 'u-ctags'}
    --disable-readcmd
    --disable-xml
    --disable-json
    --disable-seccomp
    --disable-yaml
    --disable-pcre2
    --without-included-regex
  ]
].each { system(*_1, chdir: 'u-ctags/src', exception: true) }
