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

# Auto-load FFI functions and etc. by parsing a C header file. See [the README](..) for an overview of the gem.
# 
# Most use cases are only concerned with the main method {.call} and perhaps {.ffi_module} customization.
# Other class and instance methods (most of them private) are for advanced uses such as extending the gem.
class FFI::UCtags
  class << self
    # The module for {.call} to source modules and classes *(but not constants)* from; the default is {FFI}.
    # 
    # Configure this attribute to use an alternate FFI implementation of preference, such as
    # [FFI-Plus](https://github.com/ParadoxV5/FFI-Plus) or [Nice-FFI](https://github.com/sparkchaser/nice-ffi).
    # 
    # The customized module does not have to cover all utilized FFI modules/classes –
    # {.call} will fall back to source from FFI for modules/classes not found from this module (see {.ffi_const}).
    # However, those that the module do provide must match in layouts and functionalities as those of {FFI}.
    # 
    # @return [Module & FFI::Library]
    attr_reader :ffi_module
    def ffi_module=(ffi_module)
      unless ffi_module.is_a? Module
        raise "wrong argument type #{ffi_module.class} (expected Module)"
      end
      @ffi_module = ffi_module
    end
    
    # Look up the named constant from {.ffi_module} or its ancestors, or from {FFI} if not found in that module.
    # 
    # @param name [Symbol | string]
    # @return [bot]
    def ffi_const(name)
      ffi_module.const_get(name, true)
    rescue NameError
      FFI.const_get(name, true)
    end
    
    # Create a new [`Library`](https://rubydoc.info/gems/ffi/FFI/Library) module,
    # [load](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method) the named shared library,
    # and utilize `ctags` to parse the C header located at `header_path`.
    # 
    # ```ruby
    # require 'ffi/uctags'
    # MyLib = FFI::UCtags.('mylib', 'path/to/mylib.h')
    # puts MyLib.my_function(…)
    # ```
    # 
    # @param library_name [_ToS]
    # @param header_path [_ToS]
    # @return [Module & FFI::Library]
    #   the new `Library` module with every supported construct imported
    #   (See [the README section](..#constructs--ctags-kinds-support) for a list of supported constructs)
    # 
    # @see .ffi_module
    def call(library_name, header_path)
      worker = new(library_name)
      lib = worker.library
      
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
          line.delete_suffix!(';"')
          puts "processing `#{name}` of kind `#{k}` (#{file}@#{line})" if $VERBOSE
          worker.process_kind(k, name, fields.to_h { _1.split(':', 2) })
        end
      end
      worker.close # flush the last bits
      lib
    end
    
    private :new
  end
  # Initialize class variable
  self.ffi_module = FFI
  
  # (see .ffi_const)
  def ffi_const(...) = self.class.ffi_const(...)
  
  # The [`Library`](https://rubydoc.info/gems/ffi/FFI/Library) module this instance is working on
  # 
  # @return [Module & FFI::Library]
  attr_reader :library
  
  # Create an instance for working on the named shared library.
  # The attribute {#library} is set to a new [`Library`](https://rubydoc.info/gems/ffi/FFI/Library)
  # module with the named shared library [loaded](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method).
  # 
  # @param library_name [_ToS]
  def initialize(library_name)
    @library = Module.new
    @library.extend(ffi_const :Library)
    @library.ffi_lib(library_name)
  end
  
  # Process the u-ctags kind
  # 
  # @param k [String] One-letter kind ID
  # @param name [String]
  # @param fields [Hash[String, String]]
  def process_kind(k, name, fields)
    case k
    # Functions
    when 'z' # function parameters inside function or prototype definitions
      self << typeref(fields)
    when 'p' # function prototypes
      open :attach_function
      prefix name
      suffix typeref(fields)
    # Structs/Unions
    when 'm' # struct, and union members
      self << name.to_sym
      self << typeref(fields)
    when 's' # structure names
      open @library.const_set(name, Class.new(ffi_const :Struct)), :layout
    when 'u' # union names
      open @library.const_set(name, Class.new(ffi_const :Union)), :layout
    # Miscellaneous
    when 't' # typedefs
      close
      @library.typedef typeref(fields), name.to_sym
    when 'x' # external and forward variable declarations
      close
      @library.attach_variable name, typeref(fields)
    else
      warn "\tunsupported kind ignored" if $VERBOSE
    end
  end
  
  ## Indefinite API follows ##
  
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
          @library.find_type(name_sym)
        rescue TypeError
          # Assume the unknown type is a pointer alias defined in another file.
          # This should just propagate an exception once multi-file parsing is supported.
          warn "unrecognized type #{name}, falling back to `:pointer`"
          FFI::TYPE_POINTER
        end
      end
    else # `struct` or `union` (`enum` not yet supported)
      @library.const_get(name).by_value
    end
  end
  
  def prefix(*prefixes) = @prefix = prefixes
  def suffix(*suffixes) = @suffix = suffixes
  def <<(arg) = @args << arg
  
  def open(receiver = @library, method)
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
