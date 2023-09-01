# frozen_string_literal: true

require 'ffi'
require_relative 'uctags/version'
require_relative 'uctags/directory'


# Auto-load FFI functions and etc. by parsing a C header file.
# See [the README](..) for an overview of the gem with an example.
# 
# Most use cases are only concerned with calling the main method {.call} and perhaps an {.ffi_module} customization.
# Other class and instance methods (including {#initialize}) are for advanced uses such as extending the gem.
# Since instantiating is not intended, `::new` has turned private;
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
    # The customized module does not have to cover all utilized FFI modules/classes –
    # {.call} will fall back to source from FFI for modules/classes not found from this module (see {.ffi_const}).
    # However, those the module does provide must match in layouts and functionalities as those of {FFI}.
    # 
    # @deprecated This was originally designed to integrate with alternate FFI implementations such as
    # [Nice-FFI](https://github.com/sparkchaser/nice-ffi) or another custom subset of patches.
    # However, the OG FFI library have grown to be a complete platform,
    # to the point that contributing into FFI is more practical than developing mods that may one day go obsolete.
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
    # @deprecated (see .ffi_module)
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
      #noinspection SpellCheckingInspection this command use letter flags
      cmd = %W[#{EXE_PATH} --language-force=C --param-CPreProcessor._expand=1 --kinds-C=defgmpstuxz --fields=NFPkSst --fields-C={macrodef} -nuo -] #: Array[_ToS]
      cmd.insert(2, '-V') if $DEBUG
      cmd << header_path
      IO.popen(cmd) do|cmd_out|
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
  # @deprecated (see .ffi_const)
  def ffi_const(...) = self.class.ffi_const(...)
  
  
  # The [`Library`](https://rubydoc.info/gems/ffi/FFI/Library) module this instance is working on
  # 
  # @return [Module & FFI::Library]
  attr_reader :library
  
  # A hash that maps struct/union/enum names to either:
  # * the class [singleton(FFI::Struct)] or enum [FFI::Enum] directly
  # * its (newest) {#composite_typedefs} key [Symbol], for structs/unions with typedefs.
  #   * This design allows {#const_composites} to prefer the (newest) typedef alias over the original,
  #     which is often omitted through the typedef-struct and equivalent patterns.
  # 
  # @return [Hash[Symbol, Symbol | singleton(FFI::Struct) | FFI::Enum]]
  attr_reader :composite_types
  # Table of typedef-struct/unions/enums
  # 
  # @return [Hash[Symbol, singleton(FFI::Struct) | FFI::Enum]]
  attr_reader :composite_typedefs
  # A hash that maps inner structs/unions/enums to their outer structs/unions
  # 
  # @return [Hash[singleton(FFI::Struct) | FFI::Enum, singleton(FFI::Struct)]]
  attr_reader :composite_namespacing
  
  # A LIFO array for work-in-progress constructs, most notably functions and structs.
  # The stack design enables building an inner construct (top of the stack) while putting outer constructs on hold.
  # 
  # Each element is a 3-tuple of
  # 1. a construct member queue
  # 2. a proc (or equivalent) callback
  # 3. the namespace in which this construct should define under
  # When ready, the callback is called with the populated member list (as a single arg) and the namespace.
  # 
  # @return [Array[[Array[untyped], ^(Array[untyped], String?) -> void, String?]]
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
    @library = Module.new #: FFI::library
    @library.extend(ffi_const :Library)
    @library.ffi_lib(library_name)
    
    @composite_types = {}
    @composite_typedefs = {}
    @composite_namespacing = {}
    @stack = []
    @fields = {} # `nil` error prevention
  end
  
  
  # Prepare to build a new construct. This method is designed for every new construct to call near the beginning. 
  # 
  # `Array#slice!` off topmost entries in the {#stack} according to `@fields`.
  # Invoke the callbacks of the removed entries in reverse order to ensure these previous constructs flush through.
  # Finally, if given a block, start a new stack entry with it.
  # 
  # {.call} processes a composite construct (e.g., a function or struct) as a sequence of consecutive components,
  # which starts with the construct itself followed by its original-ordered list of members
  # (e.g., function params, struct members), all as separate full-sized entries.
  # Therefore, {#stack a list} must queue the members to compile later until the next sequence commences,
  # especially since these sequences do not have terminator parts nor a member count in the header entry.
  # 
  # @example
  #   new_construct {|members, namespace| library[namespace].build_construct(members) }
  # 
  # Simpler constructs with only one u-ctags entry can simply call this method with no block (“`nil` block `&nil`”).
  # 
  # @yield a block to build the desired construct once all of the members are in
  # @yieldparam members [Array[untyped]] the populated member list
  # @yieldparam namespace [String?] the namespace in which the construct should define under
  # @return [String?]
  #   The name of the namespace this construct will define under as parsed from `@fields` (see {#process})
  def new_construct(&blk)
    full_namespace = @fields.fetch('struct') { @fields.fetch('union', nil) }
    prev_namespace = nil
    depth = if full_namespace
      full_namespace = full_namespace.split('::')
      prev_namespace = full_namespace.last #: String
      puts "\tunder `#{prev_namespace}`" if $VERBOSE
      full_namespace.size
    else
      0
    end
    if (prev = stack.slice!(depth..)) and !prev.empty?
      puts "\tflushing #{prev.size} stack entries" if $VERBOSE
      prev.reverse_each do|members, a_proc, namespace|
        if $VERBOSE
          puts "\t\twith #{members.size} members"
          puts "\t\tunder `#{namespace}`" if namespace
        end
        a_proc.(members, namespace)
      end
    end
    if blk
      puts "\tstarting new stack entry" if $VERBOSE
      stack << [[], blk, prev_namespace]
    end
    puts "\tstack has #{stack.size} entries" if $VERBOSE
    #noinspection RubyMismatchedReturnType RubyMine prefers Yardoc type over RBS type
    prev_namespace
  end
  
  # `Array#push` the given args to the top of the {#stack}.
  # 
  # @return [void]
  def stack_push(...)
    stack.last&.first&.push(...)
  end
  
  # Extract the type name from `@fields` (see {#process}).
  # 
  # Rip off names of types it nests under as all public names in C live in the same global namespace.
  # Identify and processes pointers to and arrays of structs, unions or enums.
  # 
  # Do not process the extracted name to a usable `FFI::Type`;
  # follow up with {#find_type} or {#composite_type}, or use {#extract_and_process_type} instead.
  # 
  # @return [[String, bool?]]
  #   * the name of the extracted type,
  #   * `true` if it’s a struct, union or enum, `false` if it’s a pointer to one of those, or `nil` if neither.
  def extract_type
    type_type, *_, name = @fields.fetch('typeref').split(':')
    if name.end_with?(']')
      puts "\tarray type" if $VERBOSE
      name = 'pointer' # FFI does not support typed array auto-casting for functions
        # (for struct/union members: https://github.com/ParadoxV5/FFI-UCtags/issues/14)
      is_composite = nil
    elsif 'typename'.eql?(type_type) # basic type or typedef
      name_without_star = name.dup
      is_composite = name_without_star.delete_suffix!(' *').nil? # whether pointer suffix not deleted
      if composite_typedefs.include?(name_without_star.to_sym) # typedef-composite
        name = name_without_star
        puts "\ttypedef `#{name}`" if $VERBOSE
      else # basic type
        puts "\tbasic type `#{name}`" if $VERBOSE
        is_composite = nil
      end
    else # non-typedef composite
      puts "\t#{type_type} type `#{name}`" if $VERBOSE
      is_composite = name.delete_suffix!(' *').nil? # whether pointer suffix not deleted
    end
    [name, is_composite]
  end
  
  # Find the named type from {#library}.
  # 
  # Find typedefs. Do not find structs, unions and enums; use {#composite_type} for those.
  # Fall back to `TYPE_POINTER` for unrecognized unique names.
  # 
  # @param name [String]
  # @return [FFI::Type]
  # @raise [TypeError] if the basic type is not recognized
  # @see #extract_and_process_type
  def find_type(name)
    fallback = false
    name_sym = case name
    when /\*/ # `t *`, t (*) []`, `t (*)(…)`, etc.
      :pointer
    when '_Bool'
      :bool
    when 'long double'
      :long_double
    else
      
      # Check multi-keyword integer types (does not match unconventional styles such as `int long untyped long`)
      # duplicate `int_type` capture name is intentional
      if /\A((?<unsigned>un)?signed )?((?<int_type>long|short|long long)( int)?|(?<int_type>int|char))\z/ =~ name
        #noinspection RubyResolve RubyMine cannot extract =~ local vars
        int_type.tr!(' ', '_') # namely `long long` -> 'long_long'
        #noinspection RubyResolve RubyMine cannot extract =~ local vars
        unsigned ? :"u#{int_type}" : int_type.to_sym
      else
        # use type map and fallback
        fallback = true
        name.to_sym
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
  
  # Find the named struct or union (or enum in future versions) from {#composite_types}.
  # 
  # @param name [String]
  # @return [singleton(FFI::Struct) | FFI::Enum]
  # @raise [KeyError] if this name is not registered
  # @see #extract_and_process_type
  def composite_type(name)
    # Find from {#composite_typedefs} first, process if not found
    #noinspection RubyMismatchedReturnType RubyMine cannot follow that `type` can no longer be a Symbol
    composite_typedefs.fetch(name.to_sym) do|name_sym|
      type = composite_types.fetch(name_sym)
      type.is_a?(Symbol) ? composite_typedefs.fetch(type) : type
    end
  end
  
  # {#extract_type Extract} and process ({#find_type} or {#composite_type}) the type from `@fields` (see {#process}).
  # 
  # @return [FFI::Type]
  # @raise [TypeError] if it’s a basic type with an unrecognized name
  # @raise [KeyError] if it’s a struct, union or enum with an unregistered name
  def extract_and_process_type
    name, is_composite = extract_type
    if is_composite.nil? # basic type
      find_type(name)
    else
      type = composite_type(name)
      if type.is_a? Class
        is_composite ? type.by_value : type.by_ref
      else
        is_composite ? type : @library.find_type(:pointer)
      end
    end
  end
  
  # Process the u-ctags entry.
  # 
  # This is the controller for processing various u-ctags kinds. Due to its popularity,
  # this stores the argument `fields` in `@fields` instead of passing it as an arg when calling helper methods.
  # 
  # For convenience (leading to performance), this method expects entries for composite construct
  # (e.g., a function or struct) to be consecutive. {.call} achieves this by executing u-ctags unsorted,
  # preserving the order from the original file. See {#new_construct}.
  # 
  # @note
  #   UCtags holds off from creating access points (constants) for structs/unions/enums
  #   until calling {#const_composites} (or {#close}), as they may later receive a preferred typedef name.
  # 
  # @param k [String] one-letter u-ctags kind ID
  # @param name [String] the name of the construct or component; i.e., the u-ctags tag name
  # @param fields [Hash[String, String]] additional u-ctags fields (e.g., `{'typeref' => 'typename:int'}`)
  # @return [void]
  def process(k, name, fields)
    @fields.replace(fields)
    case k
    # Functions
    when 'z' # function parameters inside function or prototype definitions
      stack_push extract_and_process_type
    when 'p', 'f' # function prototypes, function definitions
      type = extract_and_process_type # check type and fail fast
      new_construct { library.attach_function name, _1, type }
    # Structs/Unions
    when 'm' # struct, and union members
      new_construct
      stack_push name.to_sym, extract_and_process_type
    when 's' # structure names
      struct :Struct, name.to_sym
    when 'u' # union names
      struct :Union, name.to_sym
    # Enums
    when 'e' # enumerators (values inside an enumeration)
      stack_push name.to_sym
    when 'g' # enumeration names
      new_composite { composite_types[name.to_sym] = library.enum(_1) }
    # Miscellaneous
    when 't' # typedefs
      typedef name.to_sym
    when 'd' # macro definitions
      # https://github.com/ParadoxV5/FFI-UCtags/issues/2
    when 'x' # external and forward variable declarations
      new_construct
      @library.attach_variable name, extract_and_process_type
    else
      warn "\tunsupported kind ignored" if $VERBOSE
    end
  end
  
  
  # Build and record a new struct or union class
  # 
  # @param superclass [Symbol] symbol of the superclass constant (i.e., `:Struct` or `:Union`)
  # @param name [Symbol]
  # @return [singleton(FFI::Struct)]
  def struct(superclass, name)
    new_struct = Class.new(ffi_const superclass) #: singleton(FFI::Struct)
    new_composite { new_struct.layout(*_1) }
    #noinspection RubyMismatchedReturnType RubyMine ignores inline RBS annotations
    composite_types[name] = new_struct
  end
  
  # Prepare to build a new struct, union or enum.
  # 
  # @note
  #   Does not register the type in {#composite_types} –
  #   caller need to do that separately (structs/unions) or in the block (enums).
  # 
  # @yield
  #   a block to build the struct/union/enum once all of the members are in
  #   (like with {#new_construct}, but this method takes care of the `namespace` block arg)
  # @yieldparam members [Array[untyped]] the populated member list
  # @yieldreturn the new struct/union/enum
  # @return [String?]
  #   The name of the namespace this construct will define under (see {#new_construct})
  def new_composite(&blk)
    #noinspection RubyMismatchedReturnType RubyMine prefers Yardoc type over RBS type
    new_construct do|members, namespace|
      composite = blk.(members)
      composite_namespacing[composite] = composite_type(namespace) if namespace
    end
  end
  
  # Register a typedef. Register in {#library} directly for basic types;
  # store in {#composite_typedefs} (and update {#composite_types}) for structs, unions and enums.
  # 
  # @param name [Symbol] the new name
  # @return [FFI::Type | singleton(FFI::Struct) | FFI::Enum]
  def typedef(name)
    new_construct
    type_name, is_composite = extract_type
    if is_composite.nil? # basic type
      @library.typedef find_type(type_name), name
    else # composite type
      type = composite_type(type_name)
      if is_composite # configure typedef name only if not aliasing a pointer
        composite_typedefs[name] = type
        composite_types[type_name.to_sym] = name
        type
      elsif type.is_a? Class
        @library.typedef type.by_ref, name
      else
        @library.typedef :pointer, name
      end
    end
  end
  
  
  # Assign each struct, union or enum in {#composite_types} to constants.
  # 
  # If the type’s name is invalid (not capitalized), capitalize the first character if possible
  # (e.g., `qoi_desc` ➡ `Qoi_desc`), and fall back to prefixing `S_`, `U_` or `E_` depending on the type if not.
  # If names collide or the constant is already defined (e.g., due to a previous call to this method),
  # the previous definition is implicitly overridden (with Ruby complaining “already initialized constant”).
  # 
  # @return [Array[Symbol]] a list of assigned names in {#composite_types}’s order.
  def const_composites
    union_class = self.ffi_const :Union
    #noinspection RubyMismatchedReturnType RubyMine cannot follow that `type` is a Symbol when set to `name`
    composite_types.map do|name, type|
      # Prefer typedef name
      if type.is_a?(Symbol)
        name = type
        type = composite_typedefs.fetch(type)
      end
      #noinspection RubyMismatchedArgumentType RubyMine cannot follow that `type` can no longer be a Symbol
      namespace = composite_namespacing.fetch(type, @library) #: Module
      puts "\tdefining constant for construct `#{name}`" if $VERBOSE
      begin
        namespace.const_set(name, type)
        name
      rescue NameError # not a capitalized name
        # Capitalize first letter, prefix if cannot
        name = name.to_s
        first_char = name[0]
        name = if first_char&.capitalize! # capitalized
          name[0] = first_char
          name.to_sym
        elsif type.is_a? Class # struct or union
          (type < union_class) ? :"U_#{name}" : :"S_#{name}"
        else # enum (or something else)
          :"E_#{name}"
        end
        puts "\tas `#{name}`" if $VERBOSE
        namespace.const_set(name, type)
        name
      end
    end
  end
  
  # Complete the work of this instance:
  # 1. Finish up any ongoing progress (see {#new_construct})
  # 2. {#const_composites Assign structs, unions and enums to constants}
  # 
  # @note it is possible, albeit unorthodox, to continue using this instance after `close`ing it.
  # 
  # @return [Module & FFI::Library] {#library}
  def close
    puts 'finishing up' if $VERBOSE
    @fields.clear
    new_construct # flush the last construct
    const_composites
    puts 'done' if $VERBOSE
    library # return
  end
end
