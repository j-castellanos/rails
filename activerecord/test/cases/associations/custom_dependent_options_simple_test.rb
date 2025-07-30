# frozen_string_literal: true

require "cases/helper"

class CustomDependentOptionsSimpleTest < ActiveRecord::TestCase
  def setup
    # Clear any previously registered custom dependent options
    ActiveRecord::Associations::Builder::Association.custom_dependent_options.clear
  end

  def teardown
    # Clear custom dependent options after each test
    ActiveRecord::Associations::Builder::Association.custom_dependent_options.clear
  end

  # Test Handlers
  class ValidHandler
    def call(record)
      record.update_column(:name, "processed")
    end
  end

  class BulkHandler
    def call(record)
      record.update_column(:name, "individual")
    end

    def call_bulk(association, target)
      target.update_all(name: "bulk")
    end
  end

  class InvalidHandler
    # Missing call method
  end

  # Basic Registration Tests
  def test_register_custom_dependent_option_with_class
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_nil handler_info[:bulk]
  end

  def test_register_custom_dependent_option_with_block
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test) do |record|
      record.update_column(:name, "processed")
    end
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_nil handler_info[:bulk]
  end

  def test_register_custom_dependent_option_with_bulk_support
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk, BulkHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:bulk)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_not_nil handler_info[:bulk]
  end

  # Validation Tests
  def test_register_custom_dependent_option_prevents_built_in_conflicts
    assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:destroy, ValidHandler)
    end

    assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:delete_all, ValidHandler)
    end

    assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:nullify, ValidHandler)
    end
  end

  def test_register_custom_dependent_option_requires_handler
    assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test)
    end
  end

  def test_register_custom_dependent_option_prevents_both_class_and_block
    assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler) do |record|
        record.update_column(:name, "processed")
      end
    end
  end

  def test_register_custom_dependent_option_requires_call_method
    assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, InvalidHandler)
    end
  end

  def test_custom_dependent_option_handler_returns_nil_for_unknown_option
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:unknown)
    assert_nil handler_info
  end

  # Handler Functionality Tests
  def test_individual_handler_is_callable
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_respond_to handler_info[:individual], :call
  end

  def test_bulk_handler_is_callable_when_present
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk, BulkHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:bulk)
    assert_respond_to handler_info[:bulk], :call
  end

  def test_bulk_handler_is_nil_when_not_present
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    assert_nil handler_info[:bulk]
  end

  # Symbol/String Conversion Tests
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

  # Integration with Association Validation
  def test_custom_dependent_option_included_in_validation
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    # Create a temporary model class for testing
    model_class = Class.new(ActiveRecord::Base) do
      self.table_name = "companies"
    end
    
    # Should not raise an error
    assert_nothing_raised do
      model_class.class_eval do
        has_many :clients, dependent: :test
      end
    end
  end

  def test_invalid_custom_dependent_option_raises_error
    # Create a temporary model class for testing
    model_class = Class.new(ActiveRecord::Base) do
      self.table_name = "companies"
    end
    
    # Should raise an error for unregistered option
    assert_raises(ArgumentError) do
      model_class.class_eval do
        has_many :clients, dependent: :unregistered
      end
    end
  end

  # Registration State Tests
  def test_custom_dependent_options_start_empty
    # After clearing in setup, should be empty
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:nonexistent)
    assert_nil handler_info
  end

  def test_custom_dependent_options_persist_registration
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler)
    
    # Should persist across method calls
    handler_info1 = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    handler_info2 = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test)
    
    assert_not_nil handler_info1
    assert_not_nil handler_info2
    assert_equal handler_info1.class, handler_info2.class
  end

  def test_multiple_custom_dependent_options_can_be_registered
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test1, ValidHandler)
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:test2, BulkHandler)
    
    handler_info1 = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test1)
    handler_info2 = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:test2)
    
    assert_not_nil handler_info1
    assert_not_nil handler_info2
    assert_nil handler_info1[:bulk]
    assert_not_nil handler_info2[:bulk]
  end

  # Error Message Tests
  def test_built_in_conflict_error_message_includes_option_name
    error = assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:destroy, ValidHandler)
    end
    
    assert_match(/destroy/, error.message)
    assert_match(/conflicts with a built-in dependent option/, error.message)
  end

  def test_missing_handler_error_message_is_descriptive
    error = assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test)
    end
    
    assert_match(/handler class or block is required/, error.message)
  end

  def test_invalid_handler_error_message_is_descriptive
    error = assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, InvalidHandler)
    end
    
    assert_match(/must implement a #call method/, error.message)
  end

  def test_both_class_and_block_error_message_is_descriptive
    error = assert_raises(ArgumentError) do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:test, ValidHandler) do |record|
        record.update_column(:name, "processed")
      end
    end
    
    assert_match(/Cannot specify both a handler class and a block/, error.message)
  end
end