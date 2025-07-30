# frozen_string_literal: true

require "cases/helper"

class CustomDependentOptionsTest < ActiveRecord::TestCase
  fixtures :companies, :accounts, :clients

  def setup
    # Clear any previously registered custom dependent options
    ActiveRecord::Associations::Builder::Association.custom_dependent_options.clear
  end

  def teardown
    # Clear custom dependent options after each test
    ActiveRecord::Associations::Builder::Association.custom_dependent_options.clear
  end

  # Test Models
  class TestCompany < ActiveRecord::Base
    self.table_name = "companies"
  end

  class TestAccount < ActiveRecord::Base
    self.table_name = "accounts"
  end

  class TestClient < ActiveRecord::Base
    self.table_name = "clients"
  end

  # Test Handlers
  class ArchiveHandler
    def call(record)
      record.update_column(:name, "ARCHIVED: #{record.name}")
    end
  end

  class SoftDeleteHandler
    def call(record)
      record.update_column(:client_of, 999) if record.respond_to?(:client_of)
    end
  end

  class BulkArchiveHandler
    def call(record)
      record.update_column(:name, "ARCHIVED: #{record.name}")
    end

    def call_bulk(association, target)
      ids = target.pluck(:id)
      target.update_all("name = CONCAT('BULK_ARCHIVED: ', name)")
      ids
    end
  end

  class InvalidHandler
    # Missing call method
  end

  # Registration Tests
  def test_register_custom_dependent_option_with_class
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:archive)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_nil handler_info[:bulk]
  end

  def test_register_custom_dependent_option_with_block
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive) do |record|
      record.update_column(:name, "ARCHIVED: #{record.name}")
    end
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:archive)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_nil handler_info[:bulk]
  end

  def test_register_custom_dependent_option_with_bulk_support
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk_archive, BulkArchiveHandler)
    
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:bulk_archive)
    assert_not_nil handler_info
    assert_not_nil handler_info[:individual]
    assert_not_nil handler_info[:bulk]
  end

  def test_register_custom_dependent_option_prevents_built_in_conflicts
    assert_raises(ArgumentError, "Cannot register custom dependent option :destroy because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:destroy, ArchiveHandler)
    end

    assert_raises(ArgumentError, "Cannot register custom dependent option :delete_all because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:delete_all, ArchiveHandler)
    end

    assert_raises(ArgumentError, "Cannot register custom dependent option :nullify because it conflicts with a built-in dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:nullify, ArchiveHandler)
    end
  end

  def test_register_custom_dependent_option_requires_handler
    assert_raises(ArgumentError, "A handler class or block is required to register a dependent option") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive)
    end
  end

  def test_register_custom_dependent_option_prevents_both_class_and_block
    assert_raises(ArgumentError, "Cannot specify both a handler class and a block") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler) do |record|
        record.update_column(:name, "ARCHIVED")
      end
    end
  end

  def test_register_custom_dependent_option_requires_call_method
    assert_raises(ArgumentError, "Handler class must implement a #call method") do
      ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, InvalidHandler)
    end
  end

  def test_custom_dependent_option_handler_returns_nil_for_unknown_option
    handler_info = ActiveRecord::Associations::Builder::Association.custom_dependent_option_handler(:unknown)
    assert_nil handler_info
  end

  # Validation Tests
  def test_custom_dependent_option_included_in_validation
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    # Should not raise an error
    assert_nothing_raised do
      TestCompany.class_eval do
        has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
                 foreign_key: "client_of", dependent: :archive
      end
    end
  end

  def test_invalid_custom_dependent_option_raises_error
    # Should raise an error for unregistered option
    assert_raises(ArgumentError, /The :dependent option must be one of/) do
      TestCompany.class_eval do
        has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
                 foreign_key: "client_of", dependent: :unregistered
      end
    end
  end

  # has_many Association Tests
  def test_has_many_with_custom_dependent_option_individual_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    company = companies(:first_firm)
    
    # Create test association
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
    end
    
    test_company = TestCompany.find(company.id)
    original_client_names = test_company.test_clients.pluck(:name)
    
    # Destroy the company
    test_company.destroy
    
    # Verify clients were archived
    archived_clients = TestClient.where(client_of: company.id)
    archived_clients.each do |client|
      assert client.name.start_with?("ARCHIVED: "), "Expected client name to be archived, got: #{client.name}"
    end
  end

  def test_has_many_with_custom_dependent_option_bulk_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk_archive, BulkArchiveHandler)
    
    company = companies(:first_firm)
    
    # Create test association
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
               foreign_key: "client_of", dependent: :bulk_archive
    end
    
    test_company = TestCompany.find(company.id)
    original_client_names = test_company.test_clients.pluck(:name)
    
    # Destroy the company
    test_company.destroy
    
    # Verify clients were bulk archived
    archived_clients = TestClient.where(client_of: company.id)
    archived_clients.each do |client|
      assert client.name.start_with?("BULK_ARCHIVED: "), "Expected client name to be bulk archived, got: #{client.name}"
    end
  end

  # has_one Association Tests
  def test_has_one_with_custom_dependent_option
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    company = companies(:first_firm)
    
    # Create test association
    TestCompany.class_eval do
      has_one :test_account, class_name: "CustomDependentOptionsTest::TestAccount", 
              foreign_key: "firm_id", dependent: :archive
    end
    
    test_company = TestCompany.find(company.id)
    original_account = test_company.test_account
    original_name = original_account.name if original_account
    
    # Destroy the company
    test_company.destroy
    
    # Verify account was archived
    if original_account
      archived_account = TestAccount.find(original_account.id)
      assert archived_account.name.start_with?("ARCHIVED: "), "Expected account name to be archived, got: #{archived_account.name}"
    end
  end

  # belongs_to Association Tests
  def test_belongs_to_with_custom_dependent_option
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:soft_delete, SoftDeleteHandler)
    
    client = clients(:first_client)
    
    # Create test association
    TestClient.class_eval do
      belongs_to :test_company, class_name: "CustomDependentOptionsTest::TestCompany", 
                 foreign_key: "client_of", dependent: :soft_delete
    end
    
    test_client = TestClient.find(client.id)
    original_company = test_client.test_company
    
    # Destroy the client
    test_client.destroy
    
    # Verify company was soft deleted
    soft_deleted_company = TestCompany.find(original_company.id)
    assert_equal 999, soft_deleted_company.client_of, "Expected company to be soft deleted"
  end

  # Block-based Handler Tests
  def test_block_based_handler_with_has_many
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:block_archive) do |record|
      record.update_column(:name, "BLOCK_ARCHIVED: #{record.name}")
    end
    
    company = companies(:first_firm)
    
    # Create test association
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
               foreign_key: "client_of", dependent: :block_archive
    end
    
    test_company = TestCompany.find(company.id)
    
    # Destroy the company
    test_company.destroy
    
    # Verify clients were archived by block
    archived_clients = TestClient.where(client_of: company.id)
    archived_clients.each do |client|
      assert client.name.start_with?("BLOCK_ARCHIVED: "), "Expected client name to be block archived, got: #{client.name}"
    end
  end

  # Error Handling Tests
  def test_custom_dependent_option_with_nil_target
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    # Create test association
    TestCompany.class_eval do
      has_one :test_account, class_name: "CustomDependentOptionsTest::TestAccount", 
              foreign_key: "firm_id", dependent: :archive
    end
    
    # Create company without account
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    
    # Should not raise error when destroying company with no associated account
    assert_nothing_raised do
      company.destroy
    end
  end

  def test_custom_dependent_option_with_empty_collection
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    # Create test association
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
    end
    
    # Create company without clients
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    
    # Should not raise error when destroying company with no associated clients
    assert_nothing_raised do
      company.destroy
    end
  end

  # Integration Tests
  def test_custom_dependent_option_with_existing_dependent_options
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    # Should be able to use custom option alongside built-in options
    assert_nothing_raised do
      TestCompany.class_eval do
        has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
                 foreign_key: "client_of", dependent: :archive
        has_many :other_clients, class_name: "CustomDependentOptionsTest::TestClient", 
                 foreign_key: "firm_id", dependent: :destroy
      end
    end
  end

  def test_custom_dependent_option_registration_is_global
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    # Should be available to all association types
    assert_nothing_raised do
      TestCompany.class_eval do
        has_many :test_clients, class_name: "CustomDependentOptionsTest::TestClient", 
                 foreign_key: "client_of", dependent: :archive
      end
      
      TestClient.class_eval do
        belongs_to :test_company, class_name: "CustomDependentOptionsTest::TestCompany", 
                   foreign_key: "client_of", dependent: :archive
      end
    end
  end
end