require 'ffi'

class FFI::UCTags
  def initialize(namespace = FFI)
    if !namespace.is_a? Module or namespace.is_a? Class
      raise "wrong argument type #{namespace.class} (expected Module)"
    end
    @ns = (FFI >= namespace) ? namespace : Module.new.include(namespace, FFI)
  end
  
  #TODO: merge args
  # @param header_path TODO: smart find
  def call(lib_path, header_path)
    lib = Module.new.extend(@ns::Library)
    lib.ffi_lib lib_path
    
    context = nil
    cmd = "ctags --language-force=C --kinds-C=mpstuxz --fields=NFPkst -nuo - #{header_path}"
    IO.popen(cmd) do|cmd_out|
      cmd_out.each_line(chomp: true) do|line|
        name, file, line, k, *fields = line.split("\t")
        puts "processing `#{name}` of kind `#{k}` (#{file}@#{line})" if $VERBOSE
        fields = fields.to_h { _1.split(':', 2) }
        case k
          
          # Functions
          #TODO when 'p' # function prototypes
          #TODO when 'z' # function parameters inside function or prototype definitions
          
          # Structs/Unions
          #TODO when 's' # structure names
          #TODO when 'u' # union names
          #TODO when 'm' # struct, and union members
          
          # Miscellaneous
          #TODO when 't' # typedefs
          #TODO when 'x' # external and forward variable declarations
          
        else
          warn "\tunsupported kind ignored" if $VERBOSE
        end
      end
    end
  end
  def self.call(*args, namespace: FFI) = new(namespace).(*args)
end

require_relative 'uctags/version'
