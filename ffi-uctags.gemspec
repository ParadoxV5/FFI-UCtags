# frozen_string_literal: true
require_relative 'lib/ffi/uctags/version'

Gem::Specification.new do |spec|
  spec.name = 'ffi-uctags'
  spec.summary = 'Auto-load FFI functions and etc. by parsing a C header file'
  spec.version = FFI::UCtags::VERSION
  spec.required_ruby_version = '~> 3'
  
  spec.author = 'ParadoxV5'
  spec.license = 'Apache-2.0'
  
  github = 'https://github.com/ParadoxV5/FFI-UCtags'
  spec.homepage = github
  spec.metadata['source_code_uri'] = github
  spec.metadata['homepage_uri'] = github
  spec.metadata['changelog_uri'] = "#{github}/commits"
  spec.metadata['bug_tracker_uri'] = "#{github}/issues"
  spec.metadata['documentation_uri'] = 'https://ParadoxV5.github.io/FFI-UCtags/'
  
  spec.files = Dir['**/*']
  spec.require_paths = ['lib']
  spec.extensions << 'u-ctags.extconf.rb'
  
  spec.add_dependency 'ffi', '~> 1.15.0'
end
