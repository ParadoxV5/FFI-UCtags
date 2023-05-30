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
# Since instantiating is not intended, {.new the constructor} has turned private;
# of course, nothing’s stopping you from un-privatizing it.
# 
# Technical developers, you may also be interested in:
# * {#process}
#   * {#extract_and_process_type}
#     * {#composite_types}
#   * {#new_construct}
#     * {#stack}
# * {#library}
# * {#ffi_const}
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
    
    # Not a public API – see {UCtags}
    private :new
    
    # Create a new [`Library`](https://rubydoc.info/gems/ffi/FFI/Library) module,
    # [load](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method) the named shared library,
    # and utilize `ctags` to parse the C header located at `header_path`.
    # 
    # @example
    #   require 'ffi/uctags'
    #   MyLib = FFI::UCtags.('mylib', 'path/to/mylib.h')
    #   puts MyLib.my_function(…)
    # 
    # If providing a block, also evaluate it in the context of the new module (`Module#module_eval`).
    # Beware that `module_eval` does not scope constants – you have to retrieve/write them like `self::THIS`.
    # 
    # @param library_name [_ToS]
    # @param header_path [_ToS]
    # @return [Module & FFI::Library]
    #   the new `Library` module with every supported construct imported
    #   (See [the README section](..#constructs--ctags-kinds-support) for a list of supported constructs)
    # @see .ffi_module
    def call(library_name, header_path, &blk)
      instance = new(library_name)
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
          instance.process(k, name, fields.to_h { _1.split(':', 2) })
        end
      end
      instance.close.tap { _1.module_eval(&blk) if block_given? }
    end
  end
  # Initialize class variable
  self.ffi_module = FFI
  
  # Instance-level delegate for {.ffi_const}
  def ffi_const(...) = self.class.ffi_const(...)
  
  
  # The [`Library`](https://rubydoc.info/gems/ffi/FFI/Library) module this instance is working on
  # 
  # @return [Module & FFI::Library]
  attr_reader :library
  
  # A hash that maps struct/union (and enum in future versions) names to either:
  # * the class [Class] directly
  # * its (newest) {#composite_typedefs} key [Symbol], for structs/unions with typedefs.
  #   * This design allows {#const_composites} to prefer the (newest) typedef alias over the original,
  #     which is often omitted though the typedef-struct and equivalent patterns.
  # 
  # @return [Hash[Symbol, Symbol | Class]]
  attr_reader :composite_types
  # Table of typedef-struct/unions (and typedef-enums in future versions)
  # 
  # @return [Hash[Symbol, Class]]
  attr_reader :composite_typedefs
  # A hash that maps inner structs/unions (and enum in future versions) to their outer structs/unions
  # 
  # @return [Hash[Class, Class]]
  attr_reader :composite_namespacing
  
  # A LIFO array for work-in-progress constructs, most notably functions and structs.
  # The stack design enables building an inner construct (top of the stack) while putting outer constructs on hold.
  # 
  # Each element is a 2-tuple of a construct member queue and a proc (or equivalent).
  # When ready, the proc is called with the populated member list as a single arg.
  # 
  # @return [Array[[Array[untyped], ^(Array[untyped]) -> void]]
  # @see #new_construct
  attr_reader :stack
  
  # Create an instance for working on the named shared library.
  # The attribute {#library} is set to a new [`Library`](https://rubydoc.info/gems/ffi/FFI/Library)
  # module with the named shared library [loaded](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method).
  # 
  # @note `::new` is private. See {UCtags the class description} for the intention.
  # 
  # @param library_name [_ToS]
  def initialize(library_name)
    @library = Module.new
    @library.extend(ffi_const :Library)
    @library.ffi_lib(library_name)
    
    @composite_types = {}
    @composite_typedefs = {}
    @composite_namespacing = {}
    @stack = []
  end
  
  
  # Prepare building a new construct. This method is designed for every new construct to call near the beginning. 
  # 
  # `Array#slice!` off the `depth`-th entry in the {#stack} and all entries above it.
  # Invoke the procs of the removed entries in reverse order to ensure these previous constructs flush through.
  # Finally, if a given a block, start a new stack entry with it.
  # 
  # {.call} processes a composite construct (e.g., a function or struct) as a sequence of consecutive components,
  # which starts with the construct itself followed by its original-ordered list of members
  # (e.g., function params, struct members), all as separate full-sized entries.
  # Therefore, {#stack a list} must queue the members to compile later until the next sequence commences,
  # especially that these sequences do not have terminator parts nor a member count in the header entry.
  # 
  # @example
  #   new_construct { do_something_with(construct_members) }
  # 
  # Simpler constructs with only one u-ctags entry can simply call this method with no block (“`nil` block `&nil`”).
  # 
  # @param depth [int] The depth to start the construct from.
  #   * Non-negative integers refers to n-th nested levels
  #     * 0 = toplevel => clear and flush the entire stack
  #   * Negatives are relative to one deeper than the current innermost level
  #     * -1 = replace the innermost nesting => remove and flush the last stack entry
  # @return [void]
  def new_construct(depth = 0, &blk)
    stack.slice!(depth..)&.reverse_each { _2.(_1) }
    stack << [[], blk] if blk
  end
  
  
  # Extract the type name from the give u-ctags fields.
  # 
  # Rips off names of types it nests under as all public names in C live in the same global namespace.
  # Identify and processes pointers to and arrays of structs or unions (or enums in future versions).
  # 
  # Do not process the extracted name to a usable `FFI::Type`;
  # follow up with {#find_type} or {#composite_type}, or use {#extract_and_process_type} instead.
  # 
  # @param fields [Hash[String, String]] additional fields from {#process}
  # @return [[String, bool?]]
  #   * the name of the extracted type,
  #   * `true` if it’s a struct or union (or enum in future versions), `false` if it’s a pointer to one of those, or `nil` if neither.
  def extract_type(fields)
    type, *_, name = fields.fetch('typeref').split(':')
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
    # Find from {#composite_typedefs} first, process if not found
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
  # @return [void]
  def process(k, name, fields)
    case k
    # Functions
    when 'z' # function parameters inside function or prototype definitions
      stack.last&.first&.<< extract_and_process_type(fields)
    when 'p' # function prototypes
      type = extract_and_process_type(fields) # check type and fail fast
      new_construct { library.attach_function name, _1, type }
    # Structs/Unions
    when 'm' # struct, and union members
      stack.last&.first&.push name.to_sym, extract_and_process_type(fields)
    when 's' # structure names
      struct :Struct, name, fields
    when 'u' # union names
      struct :Union, name, fields
    # Miscellaneous
    when 't' # typedefs
      typedef name.to_sym, fields
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
  def struct(superclass, name, fields)
    new_struct = Class.new(ffi_const superclass)
    namespace = fields.fetch('struct') { fields.fetch('union', nil) }
    if namespace
      namespace = namespace.split('::')
      composite_namespacing[new_struct] = composite_type(namespace.last)
      depth = namespace.size
    else
      depth = 0
    end
    new_construct(depth) { new_struct.layout(*_1) }
    composite_types[name.to_sym] = new_struct
  end
  # Register a typedef. Register in {#library} directly for basic types;
  # store in `composite_typedefs` (and update `composite_types`) for structs and unions (and enums in future versions).
  # 
  # @param name [Symbol] new name
  # @param fields [Hash[String, String]] additional fields from {#process}
  # @return [FFI::Type | Class]
  def typedef(name, fields)
    new_construct
    type_name, is_pointer = extract_type(fields)
    if is_pointer.nil? # basic type
      @library.typedef find_type(type_name), name
    else # composite type
      type = composite_type(type_name)
      composite_typedefs[name] = type
      composite_types[type_name.to_sym] = name
      type
    end
  end
  
  
  # Assign each struct or union (or enum in future versions) in {#composite_types} to constants.
  # 
  # If the type’s name is invalid (not capitalized), capitalize the first character if possible
  # (e.g., `qoi_desc` ➡ `Qoi_desc`), fall back to prefixing `S_` or `U_` depending on the type if not.
  # If names collide or the constant is already defined (e.g., due to a previous call to this method),
  # the previous definition is implicitly overridden (with Ruby complaining “already initialized constant”).
  # 
  # @return [Array[Symbol]] list of assigned names in {#composite_types}’s order.
  def const_composites
    composite_types.map do |name, type|
      # Prefer typedef name
      if type.is_a?(Symbol)
        name = type
        type = composite_typedefs.fetch(type)
      end
      #noinspection RubyMismatchedArgumentType
      namespace = composite_namespacing.fetch(type, @library) #: Module
      begin
        namespace.const_set(name, type)
      rescue NameError # not a capitalized name
        # Capitalize first letter, prefix if cannot
        name = name.to_s
        first_char = name[0]
        name = if first_char&.capitalize! # capitalized
          name[0] = first_char
          name.to_sym
        elsif type < self.class.ffi_const(:Union)
          :"U_#{name}"
        else # struct
          :"S_#{name}"
        end
        namespace.const_set(name, type)
        name
      end
    end
  end
  
  # Complete the work of this instance:
  # 1. Finish up any ongoing progress (see {#new_construct})
  # 2. ({#const_composites Assign structs and unions (and enums in future versions) to constants})
  # 
  # @note it is possible, albeit unorthodox, to continue use this instance after `close`ing it.
  # 
  # @return [Module & FFI::Library] {#library}
  def close
    new_construct # flush the last construct
    const_composites
    library # return
  end
end
