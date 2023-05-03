# frozen_string_literal: true

module FFI
  module UCTags
    class Builder
      def initialize(lib)
        @lib = lib
      end
      
      def typeref(fields)
        type, name = fields.fetch('typeref').split(':', 2)
        if 'typename'.eql? type
          begin
            @lib.find_type(name.to_sym)
          rescue TypeError
            # noinspection RubyResolve
            FFI::TYPE_POINTER
          end
        else
          @lib.const_get(name).by_value
        end
      end
      
      def prefix(*prefixes) = @prefix = prefixes
      def suffix(*suffixes) = @suffix = suffixes
      def <<(arg) = @args << arg
      def call(receiver = @lib, method = nil)
        @receiver.public_send(@method, *@prefix, @args, *@suffix) if @method
        @receiver, @method = receiver, method
        @prefix, @suffix, @args = [], [], []
      end
      
    end
    private_constant :Builder
  end
end
