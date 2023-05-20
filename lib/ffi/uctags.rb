# frozen_string_literal: true

# pre-check – fail fast (raise `LoadError`) if u-ctags not found
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
  class << self
    # The module for {.call} to source modules and classes *(but not constants)* from; the default is {FFI}.
    # 
    # Configure this attribute to have UCTags use an alternate FFI implementation of preference, such as
    # [FFI-Plus](https://github.com/ParadoxV5/FFI-Plus) or [Nice-FFI](https://github.com/sparkchaser/nice-ffi).
    # 
    # The customized namespace does not have to cover all utilized FFI modules/classes –
    # {.call} will fall back to source from FFI for modules/classes not found from the namespace.
    # However, those that the namespace do provide must match in layouts and functionalities as those of {FFI}.
    # 
    # @return [Module]
    attr_reader :namespace
    def namespace=(namespace)
      if !namespace.is_a? Module or namespace.is_a? Class
        raise "wrong argument type #{namespace.class} (expected Module)"
      end
      @namespace = (FFI >= namespace) ? namespace : Module.new.include(namespace, FFI)
    end
    
    # Create a new [`Library`](https://rubydoc.info/gems/ffi/FFI/Library) module,
    # [load](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method) the library given by `library_name`,
    # and utilize `ctags` to parse the C header located at `header_path`.
    # 
    # ```ruby
    # require 'ffi/uctags'
    # MyLib = FFI::UCTags.('mylib', 'path/to/mylib.h')
    # puts MyLib.my_function(…)
    # ```
    # 
    # 
    # @return [Module]
    #   the new `Library` module with every supported construct imported
    #   (See [the README section](..#constructs--ctags-kinds-support) for a list of supported constructs)
    # 
    # @see .namespace
    def call(library_name, header_path)
      lib = Module.new
      #noinspection RubyResolve
      lib.extend(@namespace::Library)
      lib.ffi_lib library_name
      builder = Builder.new(lib)
      
      #noinspection SpellCheckingInspection
      cmd = %w[ctags --language-force=C --kinds-C=mpstuxz --fields=NFPkst -nuo -]
      cmd << '-V' if $DEBUG
      cmd << header_path
      # Run and pipe-read. `err: :err` connects command stderr to Ruby stderr
      IO.popen(cmd, err: :err) do|cmd_out|
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
            builder.open lib.const_set(name, Class.new(@namespace::Struct)), :layout
          when 'u' # union names
            builder.open lib.const_set(name, Class.new(@namespace::Union)), :layout
          
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
    
  end
  # Initialize class variable
  self.namespace = FFI
end
