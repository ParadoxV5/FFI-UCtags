# frozen_string_literal: true
require_relative '.unit_test'
class FFI::UCtags::UnitTest
  describe '.new_construct' do
    
    describe 'processing the new entry' do
      it 'does not add a new stack entry if no block given' do
        @instance.new_construct
        assert_empty @instance.stack
      end
      
      it 'adds a new stack entry if block given' do
        callback_tag = rand
        @instance.new_construct { callback_tag }
        assert_pattern do
          #noinspection RubyCaseWithoutElseBlockInspection
          case @instance.stack
          in [[ [], Proc => callback, nil ]]
            assert_same callback_tag, callback.()
          end
        end
      end
    end
    
    describe 'flushing previously-queued entries' do
      EMPTY_STACK_ENTRY = [[], proc {}, nil]

      [
        nil, # 0
        'parent', # 1
        'grandparent::parent' # 2
      ].each_with_index do|namespace, expected_size|
        (namespace ? %w[struct union] : %w[(N/A)]).each do |namespace_type|
          it "flushes until #{expected_size} stack entries if `@fields[#{namespace_type}]` has #{expected_size} names" do
            @instance.stack.push(EMPTY_STACK_ENTRY, EMPTY_STACK_ENTRY)
            @instance.fields[namespace_type] = namespace
            @instance.new_construct
            assert_same expected_size, @instance.stack.size
          end
          
          it "identifies the innermost namespace from `@fields[#{namespace_type}]`" do
            @instance.fields[namespace_type] = namespace
            return_val = @instance.new_construct {}
            queued_namespace = @instance.stack.last.last
            # Future-proofing: “DEPRECATED: Use assert_nil if expecting nil from [file:line]. This will fail in Minitest 6.”
            if namespace
              assert_equal 'parent', return_val
              assert_equal 'parent', queued_namespace
            else # nil
              assert_nil return_val
              assert_nil queued_namespace
            end
          end
        end
      end
      
      it 'runs the queued callback with the queued args' do
        args = [rand]
        namespace = rand.to_s
        callback = Minitest::Mock.new.expect(:call, nil, [args, namespace])
        @instance.stack << [args, callback, namespace]
        @instance.new_construct
        assert_mock callback
      end
    end
    
    
=begin
    # @return [String?]
    #   The name of the namespace this construct will define under as parsed from `@fields` (see {#process})
    def (&blk)
        stack << [[], blk, prev_namespace]
      prev_namespace
    end
=end
  end
  
end
