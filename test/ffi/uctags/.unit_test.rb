# frozen_string_literal: true
require 'minitest/autorun'
require 'ffi/uctags'
class FFI::UCtags::UnitTest < Minitest::Spec
  
  LIBRARY = FFI::Library::LIBC
  
  # Subclass with patches for assisting testing
  class UCtags < FFI::UCtags
    def self.new = super(LIBRARY)
    attr_accessor :fields
  end
  
  before do
    @instance = UCtags.new
  end
  
end
