# frozen_string_literal: true

# pre-check – fail fast if u-ctags not found
begin
  IO.popen(%w[ctags --version], err: :err) do|cmd_out|
    cmd_out = cmd_out.gets
    if cmd_out
      puts cmd_out if $VERBOSE
      break if cmd_out.start_with?('Universal Ctags')
    end
    raise LoadError, 'installed `ctags` is not Universal Ctags?'
  end
rescue SystemCallError
  raise LoadError, 'is Universal Ctags installed?'
end

require 'ffi'
require_relative 'uctags/version'
require_relative 'uctags/builder'

# Auto-load FFI functions and etc. by parsing a C header file. See:
# * [the README](..) for an overview of the gem
# * {.call} for an excellent starting point of your exploration
class FFI::UCTags
  # Create an instance for the provided namespace,
  # which will be where {#call} will source modules and classes *(but not constants)* from.
  # This enables utilization with alternate FFI implementations such as
  # [FFI-Plus](https://github.com/ParadoxV5/FFI-Plus) and [Nice-FFI](https://github.com/sparkchaser/nice-ffi),
  # assuming they have the same module/class layout and functionalities as FFI.
  # 
  # The namespace does not have to cover all {FFI} modules/classes, e.g., by `include`ing {FFI}.
  # {#call} will fall back to source from {FFI} for modules/classes not found from the namespace.
  # 
  # Instantiating before {#call}ing allows the same namespace to load multiple
  # [namespace`::Library`](https://rubydoc.info/gems/ffi/FFI/Library)s.
  # The class method {.call} is an alternative for one-time uses that hides the instantiation.
  # 
  # @param namespace must be a module, not a class
  def initialize(namespace = FFI)
    if !namespace.is_a? Module or namespace.is_a? Class
      raise "wrong argument type #{namespace.class} (expected Module)"
    end
    @ns = (FFI >= namespace) ? namespace : Module.new.include(namespace, FFI)
  end
  
  # The command stub {#call} invokes, for your reference
  #
  #noinspection SpellCheckingInspection
  COMMAND = %w[ctags --language-force=C --kinds-C=mpstuxz --fields=NFPkst -nuo -].freeze
  
  # Create a new [namespace`::Library`](https://rubydoc.info/gems/ffi/FFI/Library) module,
  # [load](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method) the library given by `library_name`,
  # and {COMMAND utilize `ctags`} to parse the C header located at `header_path`.
  # 
  # See
  # * [the Constructs section of the README](..#constructs--ctags-kinds-support) for a list of supported constructs
  # * {#initialize} for the role of the namespace
  # * The class method {.call}
  # 
  # @return the new `Library` module with every supported construct imported
  def call(library_name, header_path)
    lib = Module.new
    lib.extend(@ns::Library)
    lib.ffi_lib library_name
    builder = Builder.new(lib)
    
    # Run and pipe-read. `err: :err` connects command stderr to Ruby stderr
    IO.popen(COMMAND + [header_path], err: :err) do|cmd_out|
      cmd_out.each_line(chomp: true) do|line|
        # Note for maintainers: Like Ruby, C doesn’t allow use before declaration (except for functions pre-C11),
        # so we don’t need to worry about types used before they’re loaded as that’d be the library’s fault.
        name, file, line, k, *fields = line.split("\t")
        puts "processing `#{name}` of kind `#{k}` (#{file}@#{line[...-2]})" if $VERBOSE
        fields = fields.to_h { _1.split(':', 2) }
        case k
        
        # Functions
        when 'z' # function parameters inside function or prototype definitions
          builder << builder.typeref(fields)
        when 'p' # function prototypes
          builder.open :attach_function
          builder.prefix name
          builder.suffix builder.typeref(fields)
        
        # Structs/Unions
        when 'm' # struct, and union members
          builder << name.to_sym
          builder << builder.typeref(fields)
        when 's' # structure names
          builder.open lib.const_set(name, Class.new(@ns::Struct)), :layout
        when 'u' # union names
          builder.open lib.const_set(name, Class.new(@ns::Union)), :layout
        
        # Miscellaneous
        when 't' # typedefs
          builder.close
          lib.typedef builder.typeref(fields), name.to_sym
        when 'x' # external and forward variable declarations
          builder.close
          lib.attach_variable name, builder.typeref(fields)
        
        else
          warn "\tunsupported kind ignored" if $VERBOSE
        end
      end
    end
    builder.close # flush the last bits
    lib
  end
  
  # Create a temporary instance for the given `namespace` to {#call} with the remaining `args`.
  # See {#initialize} for the role of the namespace and {#call} for the main function of this gem.
  # 
  # ```ruby
  # require 'ffi/uctags'
  # MyLib = FFI::UCTags.('mylib', 'path/to/mylib.h')
  # puts MyLib.my_function(…)
  # ```
  def self.call(*args, namespace: FFI) = new(namespace).(*args)
end
