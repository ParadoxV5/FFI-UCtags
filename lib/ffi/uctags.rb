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
# Other class and instance methods (including {#initialize}) are for advanced uses such as extending the gem.
class FFI::UCtags
  class << self
    # The module for {.call} to source constants (namely modules and classes) from; the default is {FFI}.
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
    # @example
    #   require 'ffi/uctags'
    #   MyLib = FFI::UCtags.('mylib', 'path/to/mylib.h')
    #   puts MyLib.my_function(…)
    # 
    # @param library_name [_ToS]
    # @param header_path [_ToS]
    # @return [Module & FFI::Library]
    #   the new `Library` module with every supported construct imported
    #   (See [the README section](..#constructs--ctags-kinds-support) for a list of supported constructs)
    # @see .ffi_module
    def call(library_name, header_path)
      worker = new(library_name)
      #noinspection SpellCheckingInspection
      cmd = %w[ctags --language-force=C --kinds-C=mpstuxz --fields=NFPkst -nuo -]
      cmd << '-V' if $DEBUG
      cmd << header_path
      # Run and pipe-read. `err: :err` connects command stderr to Ruby stderr
      IO.popen(cmd, err: :err) do|cmd_out|
        cmd_out.each_line(chomp: true) do|line|
          # Note for maintainers:
          # For compilers’ convenience, C doesn’t allow use before declaration (except for functions pre-C11),
          # so we don’t need to worry about types used before they’re loaded as that’d be the library’s fault.
          name, file, line, k, *fields = line.split("\t")
          line.delete_suffix!(';"')
          puts "processing `#{name}` of kind `#{k}` (#{file}@#{line})" if $VERBOSE
          worker.process_kind(k, name, fields.to_h { _1.split(':', 2) })
        end
      end
      worker.finish
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
  
  # Maps struct/union (and enum in future versions) names to either
  # the class [Class] or its {#composite_typedefs} key [Symbol]
  # 
  # @return [Hash[Symbol, Symbol | Class]]
  attr_reader :composite_types
  # Records typedef-struct/unions (and typedef-enums in future versions)
  # 
  # @return [Hash[Symbol, Class]]
  attr_reader :composite_typedefs
  
  # The proc to build a composite construct from its members,
  # or `nil` if the current construct doesn’t need queued building – see {#new_construct}
  # 
  # @return [(^(*untyped) -> void)?]
  attr_accessor :construct_builder
  # A queue for composite constructs’ members – see {#new_construct}
  # 
  # @return [Array[untyped]]
  attr_reader :construct_members
  
  # Create an instance for working on the named shared library.
  # The attribute {#library} is set to a new [`Library`](https://rubydoc.info/gems/ffi/FFI/Library)
  # module with the named shared library [loaded](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method).
  # 
  # @param library_name [_ToS]
  def initialize(library_name)
    @library = Module.new
    @library.extend(ffi_const :Library)
    @library.ffi_lib(library_name)
    
    @composite_types = {}
    @composite_typedefs = {}
    @construct_members = []
  end
  
  
  # Prepare building a new construct.
  # 
  # First invoke {#construct_builder} if there’s one to ensure the previous construct flushes through,
  # Then `Array#clear` the `construct_members` and store the given block (or `nil`) as the next `construct_builder`.
  # Therefore, every new construct shall begin by call this method near the beginning.
  # 
  # {.call} processes a composite construct (e.g., a function or struct) as a sequence of consecutive components,
  # which starts with the construct itself followed by its original-ordered list of members
  # (e.g., function params, struct members), all as separate full-sized entries. Therefore, {#construct_members a list}
  # must queue the members {#construct_builder to compile later} until the next sequence commences,
  # especially that these sequences do not have terminator parts nor a member count in the header entry.
  # 
  # @example
  #   new_construct { do_something_with(construct_members) }
  # 
  # Simpler constructs with only one u-ctags entry can simply call this method with no block (“`nil` block `&nil`”).
  def new_construct(&seq_proc2)
    construct_builder&.()
    construct_members.clear
    self.construct_builder = seq_proc2
  end
  
  
  # Extract the type name from the give u-ctags fields.
  # 
  # Identify and processes pointers to and arrays of structs or unions (or enums in future versions).
  # Do not process the extracted name to a usable `FFI::Type`;
  # follow up with {#find_type} or {#composite_type}, or use {#extract_and_process_type} instead.
  # 
  # @param fields [Hash[String, String]] additional fields from {#process_kind}
  # @return [[String, bool?]]
  #   * the name of the extracted type,
  #   * `true` if it’s a struct or union (or enum in future versions), `false` if it’s a pointer to one of those, or `nil` if neither.
  def extract_type(fields)
    type, name = fields.fetch('typeref').split(':', 2)
    if 'typename'.eql?(type) # basic type
      [name, nil]
    elsif name.end_with?('[]') # array
      ['void *', nil] # FFI does not support typed array auto-casting
    else
      [name, name.delete_suffix!(' *').nil?] # […, whether pointer suffix not deleted]
    end
  end
  
  # Find the named type from {#library}.
  # 
  # Find typedefs. Do not find structs, unions and enums (future versions); use {#composite_type} for those.
  # Fall back to `TYPE_POINTER` for unrecognized unique names.
  # 
  # @param name [String]
  # @return [FFI::Type]
  # @raise [TypeError] if the basic type is not recognized
  # @see #extract_and_process_type
  def find_type(name)
    composite_typedefs.fetch(name.to_sym) do|name_sym|
      fallback = false
      name_sym = case name
        when /[*\[]/ # `t *`, `t []`, `t (*) []`, `t (*)(…)`, etc.
          :pointer
        when '_Bool'
          :bool
        when 'long double'
          :long_double
        else
          
          # Check multi-keyword integer types (does not match unconventional styles such as `int long untyped long`)
          # duplicate `int_type` capture name is intentional
          if /\A((?<unsigned>un)?signed )?((?<int_type>long|short|long long)( int)?|(?<int_type>int|char))\z/ =~ name
            #noinspection RubyResolve
            int_type.tr!(' ', '_') # namely `long long` -> 'long_long'
            #noinspection RubyResolve
            unsigned ? :"u#{int_type}" : int_type.to_sym
          else
            # use type map and fallback
            fallback = true
            name_sym
          end
        end
      
      begin
        @library.find_type(name_sym)
      rescue TypeError => e
        raise e unless fallback
        # Assume the unknown type is a pointer alias defined in another file.
        # This should just propagate an exception once multi-file parsing is supported.
        warn "unrecognized type `#{name}`, falling back to `TYPE_POINTER`"
        ffi_const :TYPE_POINTER
      end
    end
  end
  
  # Find the named struct or union (or enum in future versions) from {#composite_types}.
  # 
  # @param name [String]
  # @return [Class]
  # @raise [KeyError] if this name is not registered
  # @see #extract_and_process_type
  def composite_type(name)
    type = composite_types.fetch(name.to_sym)
    #noinspection RubyMismatchedReturnType
    type.is_a?(Symbol) ? composite_typedefs.fetch(type) : type
  end
  
  # {#extract_type Extract} and process ({#find_type} or {#composite_type}) the type from the give u-ctags fields.
  # 
  # @param (see #extract_type)
  # @return [FFI::Type]
  # @raise [TypeError] if it’s a basic type with an unrecognized name
  # @raise [KeyError] if it’s a struct or union (or enum in future versions) with an unregistered name
  def extract_and_process_type(...)
    name, is_pointer = extract_type(...)
    if is_pointer.nil? # basic type
      find_type(name)
    else
      type = composite_type(name)
      is_pointer ? type.by_ref : type.by_value
    end
  end
  
  # Process the u-ctags kind.
  # 
  # For convenience (leading to performance), this method expects entries for composite construct
  # (e.g., a function or struct) be consecutive. {.call} achieves this by executing u-ctags unsorted,
  # preserving the order from the original file. See {#new_construct}.
  # 
  # @param k [String] one-letter kind ID
  # @param name [String]
  # @param fields [Hash[String, String]] additional fields
  def process_kind(k, name, fields)
    case k
    # Functions
    when 'z' # function parameters inside function or prototype definitions
      construct_members << extract_and_process_type(fields)
    when 'p' # function prototypes
      type = extract_and_process_type(fields) # check type and fail fast
      new_construct { library.attach_function name, construct_members, type }
    # Structs/Unions
    when 'm' # struct, and union members
      construct_members.push name.to_sym, extract_and_process_type(fields)
    when 's' # structure names
      struct :Struct, name
    when 'u' # union names
      struct :Union, name
    # Miscellaneous
    when 't' # typedefs
      typedef(name, fields)
    when 'x' # external and forward variable declarations
      new_construct
      @library.attach_variable name, extract_and_process_type(fields)
    else
      warn "\tunsupported kind ignored" if $VERBOSE
    end
  end
  
  
  # Build and record a new struct or union class
  # 
  # @param superclass [Symbol] symbol of the superclass constant (i.e., `:Struct` or `:Union`)
  # @param name [String]
  # @return [Class]
  def struct(superclass, name)
    new_struct = Class.new(ffi_const superclass)
    new_construct { new_struct.layout *construct_members }
    composite_types[name.to_sym] = new_struct
  end
  # Register a typedef. Register in {#library} directly for basic types;
  # store in `composite_typedefs` (and update `composite_types`) for structs and unions (and enums in future versions).
  # 
  # @param name [String] new name
  # @param fields [Hash[String, String]] additional fields from {#process_kind}
  def typedef(name, fields)
    name = name.to_sym
    new_construct
    type_name, is_pointer = extract_type(fields)
    if is_pointer.nil? # basic type
      @library.typedef find_type(type_name), name
    else # structural type
      type_name = type_name.to_sym
      composite_typedefs[name] = composite_types.fetch(type_name)
      composite_types[type_name] = name
    end
  end
  
  
  ## Indefinite API follows ##
  
  private
  
  public def finish
    new_construct # flush the last bits
    composite_types.each do |name, type|
      # Prefer typedef name
      if type.is_a?(Symbol)
        name = type
        type = composite_typedefs.fetch(type)
      end
      begin
        #noinspection RubyMismatchedArgumentType
        @library.const_set(name, type)
      rescue NameError
        # Capitalize first letter, prefix if cannot
        name = name.to_s
        first_char = name[0]
        #noinspection RubyNilAnalysis
        @library.const_set(
          if first_char.capitalize! # capitalized
            name[0] = first_char
            name
          elsif type < self.class.ffi_const(:Union)
            "U_#{name}"
          else # struct
            "S_#{name}"
          end,
          type
        )
      end
    end
    library
  end
end
