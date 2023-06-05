FFI-UCtags for Ruby is a utility gem that
[loads an FFI library](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method)
by reading a list of constructs to import off a C header file.

**Prerequisite:** [Universal Ctags](https://ctags.io) (v6.0.0 tested) – does the heavy-lifting of parsing the header.
This gem doesn’t bundle u-ctags for the time being (insights welcome!);
requiring *the user* to separately install u-ctags impacts the distribution of the gem ports.

This gem is still developing; but once mature,
Ruby ports for C libraries are free from the duty of tracking the APIs manually!
Just download the header, find a pre-built shared library or two if going multi-platform,
and feed them into this utility.
Maybe complement with a few Ruby scripts to enable OOP convenience, and boom, libXXX ported in less than an hour!

**Caution:** Currently, this project does not have automated testing (also insights welcome!),
instead relies on code review and small test subjects.


## Example: QOI

[phoboslab/qoi@dfc056e](https://github.com/phoboslab/qoi/tree/dfc056e813c98d307238d35f7f041a725d699dfc)
```ruby
require 'ffi-uctags'

# Import QOI library in one line
QOI = FFI::UCtags.call 'path/to/libqoi.so', 'path/to/qoi.h'

# Build a Struct
meta = QOI::Qoi_desc.new
meta[:width] = meta[:height] = 3
meta[:channels] = 4
meta[:colorspace] = 0 # QOI_SRGB

# Use the library like how you would with manually-imported FFI
bytes = 0
FFI::MemoryPointer.new(:uint32, 9) do|pixels|
  pixels.write_array_of_uint32 [
    # AABBGGRR (most architectures store integers in little-endian)
    0x00000000, 0xFF000000, 0xFFFFFFFF,
    0xFF0000FF, 0xFF00FF00, 0xFFFF0000,
    0xFF00FFFF, 0xFFFF00FF, 0xFFFFFF00
  ]
  bytes = QOI.qoi_write('path/to/output.qoi', pixels, meta)
end

puts "Written #{bytes} bytes"
exit !bytes.zero? # `#qoi_write` returns 0 on failure
```


## Constructs & Ctags kinds support

### ☑️️ Developed
* Recognition of basic C types (`unsigned char`, `int8_t`, etc.)
* Function Prototypes
  * `p` function prototypes
  * `z` function parameters inside function or prototype definitions
* Miscellaneous
  * `t` typedefs
  * `x` external and forward variable declarations

### 📝 Developing
* Structs/Unions
  * `m` struct, and union members
  * `s` structure names
  * `u` union names
  * nested structs and unions
  * currently does not recognize pointer to struct/union typedefs ([#7](https://github.com/ParadoxV5/FFI-UCtags/issues/7))

### 🔜 To Do
* Enums ([#1](https://github.com/ParadoxV5/FFI-UCtags/issues/1))
  * `e` enumerators (values inside an enumeration)
  * `g` enumeration names
* Literal Macros (macro-defined constants) ([#2](https://github.com/ParadoxV5/FFI-UCtags/issues/2))
  * `d` macro definitions
* FFI callbacks (wraps pointer to functions) ([#3](https://github.com/ParadoxV5/FFI-UCtags/issues/3))
* Variadic args ([#4](https://github.com/ParadoxV5/FFI-UCtags/issues/4))
* Definitions (contrast with *prototypes*, which are declarations only ([#6](https://github.com/ParadoxV5/FFI-UCtags/issues/6))
  * `f` function definitions
  * `v` variable definitions
  * By convention, though, C headers are supposed to be all declarations and no implementation.

### ⏳ No Plans Yet
* Import referenced headers (i.e., nested imports) ([#5](https://github.com/ParadoxV5/FFI-UCtags/issues/5))
  * `h` included header files
* Enums that aren’t simply `0...size`
  * Let me or the u-ctags team know if this is a much-wanted feature.
* FFI Types `:string`, `:strptr` and `:buffer_*`
* Structs/unions defined inside functions’ parameter list
  * E.g., `void dubious_function(struct { … } data);`
  * They are not recognized by u-ctags
  * “C allows `struct`, `union`, and `enum` types to be declared in function prototypes, whereas C++ does not.”
    ⸺ [Wikipedia](https://en.wikipedia.org/wiki/Compatibility_of_C_and_C%2B%2B?oldid=1153847754#Constructs_valid_in_C_but_not_in_C++)
* Parameterized Macros
  * `D` parameters inside macro definitions

### 🧊 Nope
* Non-literal Macros (i.e., C code macros)
* Miscellaneous Ctags Kinds
  * `l` local variables
  * `L` goto labels


## Additional capabilities

* Passive design enables working with alternate FFI implementations such as [Nice-FFI](https://github.com/sparkchaser/nice-ffi)

### Regarding structs and unions

Structs and unions are classes in FFI, thus this gem chooses to import them as constants.
Top-level structs/unions are under the imported `FFI::Library`’s namespace,
while inner structs/unions nest under outer ones.

Whereas FFI imports typedefs as Symbol keys of a table of types,
this gem handles typedefs of struct/unions specially to import them as constants.
The gem prefers typedef aliases over original names,
which is often omitted though the typedef-struct and typedef-union patterns. For example:
```c
struct MyStruct { // Named, but must prefix `struct ` every use (`struct MyStruct`)
  …
}
typedef struct { // No name
  …
} MyStruct_t; // The name `MyStruct_t` actually belongs to a typedef.
```
This gem imports the first struct as `MyStruct` and the second as `MyStruct_t`
(rather than some anonymous id generated by u-ctags).

Since Ruby constants must start with an uppercase letter,
this gem capitalizes the first char for names that don’t meet the criterion,
or prefix with `S` or `U` for ones that don’t start with a capitalizable char (typically `_`).
For example, the struct in [the example above](#example-qoi) is typedef-named `qoi_desc` in the original header;
it becomes `Qoi_desc` to meet the capitalization criterion.

Structs and unions with neither a name nor typedef aliases use placeholder names generated by u-ctags,
which is `__anon###` where `###` is a hash ID, thus you’d find them around with `S__anon` or `U__anon` prefixes.
The hash is consistent as long as the `path/to/header.h` is the same.
See: https://github.com/universal-ctags/ctags/blob/v6.0.0/docs/parser-cxx.rst#anonymous-structure-names


## U-ctags limitation: Macros

U-ctags is not a C preprocessor. It currently only follows preprocessing directives naïvely.
Preprocessor macros can confuse u-ctags (and consequently this gem) to parse inappropriate constructs,
especially templates that generate content.

See: [universal-ctags/ctags#2356](https://github.com/universal-ctags/ctags/issues/2356)

Meanwhile, patching headers and/or preprocessing them (e.g., `gcc -E`) works this problem around.


## License

Copyright 2023 ParadoxV5

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

> http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
