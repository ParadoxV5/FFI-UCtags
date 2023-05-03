require 'ffi'

class FFI::UCTags
  def initialize(namespace = FFI)
    if !namespace.is_a? Module or namespace.is_a? Class
      raise "wrong argument type #{namespace.class} (expected Module)"
    end
    @ns =  (namespace <= FFI) ? namespace : Module.new.include(namespace, FFI)
  end
  
end

require_relative 'uctags/version'
