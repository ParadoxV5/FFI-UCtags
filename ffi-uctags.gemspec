# frozen_string_literal: true
require_relative 'lib/ffi/uctags/version'

Gem::Specification.new do |spec|
  spec.name = 'ffi-uctags'
  spec.summary = 'Auto-load FFI functions and etc. by using u-ctags to parse a C header file'
  spec.version = FFI::UCtags::VERSION
  spec.author = 'ParadoxV5'
  spec.license = 'Apache-2.0'
  
  github_account = spec.author
  github = File.join 'https://github.com', github_account, 'FFI-UCtags'
  spec.homepage = github
  spec.metadata = {
    'homepage_uri'      => spec.homepage,
    'source_code_uri'   => github,
    'changelog_uri'     => File.join(github, 'releases'),
    'bug_tracker_uri'   => File.join(github, 'issues'),
    'wiki_uri'          => File.join(github, 'wiki'),
    'funding_uri'       => File.join('https://github.com/sponsors', github_account),
    'documentation_uri' => File.join('https://rubydoc.info/gems', spec.name)
  }

  spec.files = Dir['**/*']
  spec.extensions << 'Rakefile'
  
  spec.required_ruby_version = '>= 3'
  spec.add_dependency 'ffi', '>= 1.15', '< 1.17'
  spec.add_dependency 'rake', '~> 13.0.0'
end
