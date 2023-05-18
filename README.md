FFI-UCTags for Ruby is a utility gem that
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
  * currently crashes on anonymous structs/unions or ones with non-capitalized names

### 🔜 To Do
* Enums
  * `e` enumerators (values inside an enumeration)
  * `g` enumeration names
* Literal Macros (macro-defined constants)
  * `d` macro definitions
* FFI callbacks (wraps pointer to functions) and auto-cast for struct/union pointers

### ⏳ No Plans Yet
* Enums that aren’t simply `0...size`
  * Let me or the u-ctags team know if this is a much-wanted feature.
* Variadic args
* FFI Types `:string`, `:strptr` and `:buffer_*`
* Import referenced headers (i.e., nested imports)
  * `h` included header files
* Definitions (C headers are supposed to only have declarations)
  * `f` function definitions
  * `v` variable definitions
* Parameterized Macros
  * `D` parameters inside macro definitions

### 🧊 Nope
* Non-literal Macros (i.e., C code macros)
* Miscellaneous Ctags Kinds
  * `L` goto labels


## U-Ctags limitation: Macros

U-Ctags is not a C preprocessor. It currently only follows preprocessing directives naïvely.
Preprocessor macros can confuse U-Ctags (and consequently this gem) to parse inappropriate constructs,
especially templates that generate content.

See: https://github.com/universal-ctags/ctags/issues/2356

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
