FFI-UCTags for Ruby is a utility gem that
[loads an FFI library](https://rubydoc.info/gems/ffi/FFI/Library#ffi_lib-instance_method)
by reading a list of constructs to import off a C header file.

**Prerequisite:** [Universal Ctags](https://ctags.io/) (v5.9.0 tested) – does the heavy-lifting of parsing the header.
This gem doesn’t bundle u-ctags for the time being (insights welcome!);
requiring *the user* to separately install u-ctags impacts the distribution of the gem ports.

This gem is still developing; but once mature,
Ruby ports for C libraries are free of the duty of updating the APIs manually!
Just download the header, find a pre-built shared library or two if going multi-platform,
and feed them into this utility.
Maybe complement with a few Ruby scripts to enable OOP convenience, and boom, libXXX ported in less than an hour!

**Caution:** Currently, this project does not have automated testing (also insights welcome!),
instead relies on code review and small test subjects.


## Constructs & Ctags kinds support

### ☑️️ Developed
* Function Prototypes
  * `p` function prototypes
  * `z` function parameters inside function or prototype definitions
* Miscellaneous
  * `t` typedefs
  * `x` external and forward variable declarations

### 📝 Developing
* C Types
  * no support yet for multi-word types, e.g., `unsigned int`
* Structs/Unions
  * `m` struct, and union members
  * `s` structure names
  * `u` union names
  * currently only recognizes pass-by-value and treats pass-by-reference the same as other generic pointers
  * currently crashes on anonymous structs/unions or ones with non-capitalized names

### 🔜 To Do
* Varargs
* Enums
  * `e` enumerators (values inside an enumeration)
  * `g` enumeration names
* Literal Macros (macro-defined constants)
  * `d` macro definitions

### ⏳ No Plans Yet
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
