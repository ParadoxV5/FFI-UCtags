# Configure u-ctags
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

# Create Makefile that forwards select `TARGETS` to [u-ctags Makefile](u-ctags/src/Makefile)
File.write("Makefile", <<EOF)
TARGETS := all install uninstall clean distclean 
.PHONY: $(TARGETS) help
$(TARGETS)::
\t$(MAKE) -C u-ctags/src $@
distclean::
\t-rm -f Makefile
help:
\t@echo "Make corresponding u-ctags target (one of: $(TARGETS))"
EOF
