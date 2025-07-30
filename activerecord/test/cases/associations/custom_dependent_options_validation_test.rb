# frozen_string_literal: true

require "cases/helper"

class CustomDependentOptionsValidationTest < ActiveRecord::TestCase
  def setup
    # Clear any previously registered custom dependent options
    ActiveRecord::Associations::Builder::Association.custom_dependent_options.clear
  end

  def teardown
    # Clear custom dependent options after each test
    ActiveRecord::Associations::Builder::Association.custom_dependent_options.clear
  end

  class TestModel < ActiveRecord::Base
    self.table_name = "companies"
  end

  class ValidHandler
    def call(record)
      record.update_column(:name, "processed")
    end
  end

  class BulkValidHandler
    def call(record)
      record.update_column(:name, "processed")
    end

    def call_bulk(association, target)
      target.update_all(name: "bulk_processed")
    end
  end

  class InvalidHandler
    # Missing call method
  end

  class InvalidCallableHandler
    def call
      # Wrong arity - should accept one argument
    end
  end

  # Registration Validation Tests
  def test_register_dependent_option_with_valid_class
    assert_nothing_raised do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    end

    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_nil handler_info[:bulk]
  end

  def test_register_dependent_option_with_bulk_handler
    assert_nothing_raised do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, BulkValidHandler)
    end

    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_not_nil handler_info[:bulk]
  end

  def test_register_dependent_option_with_valid_block
    assert_nothing_raised do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test) do |record|
        record.update_column(:name, "processed")
      end
    end

    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_nil handler_info[:bulk]
  end

  def test_register_dependent_option_rejects_invalid_class
    assert_raises(ArgumentError, "Handler class must implement a #call method") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, InvalidHandler)
    end
  end

  def test_register_dependent_option_rejects_no_handler
    assert_raises(ArgumentError, "A handler class or block is required to register a dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test)
    end
  end

  def test_register_dependent_option_rejects_both_class_and_block
    assert_raises(ArgumentError, "Cannot specify both a handler class and a block") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler) do |record|
        record.update_column(:name, "processed")
      end
    end
  end

  # Built-in Option Conflict Tests
  def test_register_dependent_option_rejects_destroy_conflict
    assert_raises(ArgumentError, "Cannot register custom dependent option :destroy because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:destroy, ValidHandler)
    end
  end

  def test_register_dependent_option_rejects_destroy_async_conflict
    assert_raises(ArgumentError, "Cannot register custom dependent option :destroy_async because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:destroy_async, ValidHandler)
    end
  end

  def test_register_dependent_option_rejects_delete_conflict
    assert_raises(ArgumentError, "Cannot register custom dependent option :delete because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:delete, ValidHandler)
    end
  end

  def test_register_dependent_option_rejects_delete_all_conflict
    assert_raises(ArgumentError, "Cannot register custom dependent option :delete_all because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:delete_all, ValidHandler)
    end
  end

  def test_register_dependent_option_rejects_nullify_conflict
    assert_raises(ArgumentError, "Cannot register custom dependent option :nullify because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:nullify, ValidHandler)
    end
  end

  def test_register_dependent_option_rejects_restrict_with_error_conflict
    assert_raises(ArgumentError, "Cannot register custom dependent option :restrict_with_error because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:restrict_with_error, ValidHandler)
    end
  end

  def test_register_dependent_option_rejects_restrict_with_exception_conflict
    assert_raises(ArgumentError, "Cannot register custom dependent option :restrict_with_exception because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:restrict_with_exception, ValidHandler)
    end
  end

  # Association Validation Tests
  def test_custom_dependent_option_validation_in_has_many
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)

    assert_nothing_raised do
      TestModel.class_eval do
        has_many :test_clients, class_name: "Client", foreign_key: "client_of", dependent: :test
      end
    end
  end

  def test_custom_dependent_option_validation_in_has_one
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)

    assert_nothing_raised do
      TestModel.class_eval do
        has_one :test_account, class_name: "Account", foreign_key: "firm_id", dependent: :test
      end
    end
  end

  def test_custom_dependent_option_validation_in_belongs_to
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)

    assert_nothing_raised do
      TestModel.class_eval do
        belongs_to :test_company, class_name: "Company", foreign_key: "client_of", dependent: :test
      end
    end
  end

  def test_unregistered_custom_dependent_option_raises_error
    assert_raises(ArgumentError, /The :dependent option must be one of/) do
      TestModel.class_eval do
        has_many :test_clients, class_name: "Client", foreign_key: "client_of", dependent: :unregistered
      end
    end
  end

  def test_custom_dependent_option_included_in_validation_error_message
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)

    error = assert_raises(ArgumentError) do
      TestModel.class_eval do
        has_many :test_clients, class_name: "Client", foreign_key: "client_of", dependent: :unregistered
      end
    end

    assert_match(/test/, error.message, "Expected error message to include registered custom option")
  end

  # Handler Retrieval Tests
  def test_custom_dependent_option_handler_returns_nil_for_unknown
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:unknown)
    assert_nil handler_info
  end

  def test_custom_dependent_option_handler_returns_info_for_registered
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
    assert_kind_of Hash, handler_info
    assert handler_info.key?(:individual)
    assert handler_info.key?(:bulk)
  end

  def test_custom_dependent_option_handler_individual_is_callable
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_respond_to handler_info[:individual], :call
  end

  def test_custom_dependent_option_handler_bulk_is_callable_when_present
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, BulkValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_respond_to handler_info[:bulk], :call
  end

  def test_custom_dependent_option_handler_bulk_is_nil_when_not_present
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_nil handler_info[:bulk]
  end

  # Symbol Conversion Tests
  def test_register_dependent_option_converts_string_to_symbol
    ActiveRecord::Associations::Builder::Association.register_dependent_option("test", ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
    
    # Should also work with string
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler("test")
    assert_not_nil handler_info
  end

  def test_register_dependent_option_handles_symbol_input
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
  end

  # Thread Safety Tests
  def test_custom_dependent_options_registration_is_thread_safe
    threads = []
    
    10.times do |i|
      threads << Thread.new do
        handler_class = Class.new do
          def call(record)
            record.update_column(:name, "processed_#{Thread.current.object_id}")
          end
        end
        
        ActiveRecord::Associations::Builder::Association.register_dependent_option(:"test_#{i}", handler_class)
      end
    end
    
    threads.each(&:join)
    
    # Verify all options were registered
    10.times do |i|
      handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:"test_#{i}")
      assert_not_nil handler_info, "Expected handler for test_#{i} to be registered"
    end
  end
end