# frozen_string_literal: true
require_relative '.unit_test'
class FFI::UCtags::UnitTest
  describe 'self.new' do
    
    it 'loads the given library' do
      assert_includes @instance.library.ffi_libraries.map(&:name), LIBRARY
    end
    
    it 'initializes instance variables' do
      {
        composite_types: Hash,
        composite_typedefs: Hash,
        composite_namespacing: Hash,
        stack: Array,
        fields: Hash
      }.each do|attr, klass|
        value = @instance.public_send attr
        assert_kind_of klass, value
        assert_empty value
      end
    end
    
  end
end
