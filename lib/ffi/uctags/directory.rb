# This file locates where the u-ctags executable is.

# The parent namespace which this gem integrates with.
# Check out [the FFI wiki](https://github.com/ffi/ffi/wiki) for guides on the FFI gem.
module FFI
  class UCtags
    # Absolute path to the Universal Ctags root (`PREFIX`) where the `bin` and `src` folders are located.
    EXE_ROOT = File.expand_path('../../../../u-ctags/', __FILE__).freeze
    # Absolute path to the Universal `ctags` executable – {EXE_ROOT}`/bin/ctags`.
    EXE_PATH  = File.join(EXE_ROOT, 'bin/ctags').freeze
  end
end
