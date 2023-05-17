# frozen_string_literal: true
require 'ffi'

class FFI::UCTags
  # Helper for {FFI::UCTags}. Indefinite API – not for external use (yet?).
  class Builder
    def initialize(lib)
      @lib = lib
    end
    
    #noinspection RubyResolve
    def typeref(fields)
      type, name = fields.fetch('typeref').split(':', 2)
      if 'typename'.eql? type # non-derived type
        case name
        when /[*\[]/ # `t *`, `t []`, `t (*) []`, `t (*)(…)`, etc.
          FFI::TYPE_POINTER
        when '_Bool'
          FFI::TYPE_BOOL
        when 'long double'
          FFI::TYPE_LONGDOUBLE
        else
          # Check multi-keyword integer types (does not match unconventional styles such as `int long untyped long`)
          # duplicate `t` capture name is intentional
          if /\A((?<unsigned>un)?signed )?((?<int_type>long|short|long long)( int)?|(?<int_type>int|char))\z/ =~ name
            int_type.tr!(' ', '_') # namely `long long` -> 'long_long'
            unsigned ? :"u#{int_type}" : int_type.to_sym
          else
            name.to_sym # Fall back to type map
          end.then do|name_sym|
            @lib.find_type(name_sym)
          rescue TypeError
            # Assume the unknown type is a pointer alias defined in another file.
            # This should just propagate an exception once multi-file parsing is supported.
            warn "unrecognized type #{name}, falling back to `:pointer`"
            FFI::TYPE_POINTER
          end
        end
      else # `struct` or `union` (`enum` not yet supported)
        @lib.const_get(name).by_value
      end
    end
    
    def prefix(*prefixes) = @prefix = prefixes
    def suffix(*suffixes) = @suffix = suffixes
    def <<(arg) = @args << arg
    
    def open(receiver = @lib, method)
      if @method
        if @prefix.empty? and @suffix.empty?
          @receiver.public_send(@method, *@args)
        else
          @receiver.public_send(@method, *@prefix, @args, *@suffix)
        end
      end
      @receiver, @method = receiver, method
      @prefix, @suffix, @args = [], [], []
    end
    def close = open nil, nil
  end
  private_constant :Builder
end
