# frozen_string_literal: true
require 'ffi'
require_relative 'uctags/builder'

class FFI::UCTags
  def initialize(namespace = FFI)
    if !namespace.is_a? Module or namespace.is_a? Class
      raise "wrong argument type #{namespace.class} (expected Module)"
    end
    @ns = (FFI >= namespace) ? namespace : Module.new.include(namespace, FFI)
  end
  
  # noinspection SpellCheckingInspection
  COMMAND = %w[ctags --language-force=C --kinds-C=mpstuxz --fields=NFPkst -nuo -].freeze
  #TODO: merge args
  # @param header_path TODO: smart find
  def call(lib_path, header_path)
    lib = Module.new.extend(@ns::Library)
    lib.ffi_lib lib_path
    builder = Builder.new(lib)
    IO.popen(COMMAND + [header_path], err: :err) do|cmd_out|
      cmd_out.each_line(chomp: true) do|line|
        name, file, line, k, *fields = line.split("\t")
        puts "processing `#{name}` of kind `#{k}` (#{file}@#{line})" if $VERBOSE
        fields = fields.to_h { _1.split(':', 2) }
        case k
          
          # Functions
          when 'z' # function parameters inside function or prototype definitions
            builder << builder.typeref(fields)
          when 'p' # function prototypes
            builder.call :attach_function
            builder.prefix name
            builder.suffix builder.typeref(fields)
          
          # Structs/Unions
          when 'm' # struct, and union members
            builder << name.to_sym
            builder << builder.typeref(fields)
          when 's' # structure names
            builder.call lib.const_set(name, @ns::Struct.new), :layout
          when 'u' # union names
            builder.call lib.const_set(name, @ns::Union.new), :layout
          
          # Miscellaneous
          when 't' # typedefs
            builder.call
            lib.typedef name.to_sym, builder.typeref(fields)
          when 'x' # external and forward variable declarations
            builder.call
            lib.attach_variable name, builder.typeref(fields)
        else
          warn "\tunsupported kind ignored" if $VERBOSE
        end
      end
    end
    builder.call
    lib
  end
  def self.call(*args, namespace: FFI) = new(namespace).(*args)
end

require_relative 'uctags/version'
