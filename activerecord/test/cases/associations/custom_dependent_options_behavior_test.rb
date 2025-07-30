# frozen_string_literal: true

require "cases/helper"

class CustomDependentOptionsBehaviorTest < ActiveRecord::TestCase
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

  class TestClient < ActiveRecord::Base
    self.table_name = "clients"
  end

  class TestAccount < ActiveRecord::Base
    self.table_name = "accounts"
  end

  # Test Handlers
  class ArchiveHandler
    def call(record)
      record.update_columns(name: "ARCHIVED: #{record.name}")
    end
  end

  class SoftDeleteHandler
    def call(record)
      record.update_columns(name: "DELETED: #{record.name}")
    end
  end

  class BulkArchiveHandler
    def call(record)
      record.update_columns(name: "INDIVIDUAL: #{record.name}")
    end

    def call_bulk(association, target)
      target.update_all("name = CONCAT('BULK: ', name)")
    end
  end

  class CountingHandler
    @@call_count = 0
    @@bulk_call_count = 0

    def self.reset_counts
      @@call_count = 0
      @@bulk_call_count = 0
    end

    def self.call_count
      @@call_count
    end

    def self.bulk_call_count
      @@bulk_call_count
    end

    def call(record)
      @@call_count += 1
      record.update_columns(name: "COUNTED: #{record.name}")
    end

    def call_bulk(association, target)
      @@bulk_call_count += 1
      target.update_all("name = CONCAT('BULK_COUNTED: ', name)")
    end
  end

  class CallbackTriggeringHandler
    def call(record)
      # Use update to trigger callbacks
      record.update(name: "CALLBACK: #{record.name}")
    end
  end

  class ErrorRaisingHandler
    def call(record)
      raise "Handler error for #{record.name}"
    end
  end

  # Individual Record Processing Tests
  def test_has_many_individual_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client1 = TestClient.create!(name: "Client 1", client_of: company.id)
    client2 = TestClient.create!(name: "Client 2", client_of: company.id)
    
    company.destroy
    
    # Verify each client was processed individually
    client1.reload
    client2.reload
    assert_equal "ARCHIVED: Client 1", client1.name
    assert_equal "ARCHIVED: Client 2", client2.name
  end

  def test_has_one_individual_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_one :test_account, class_name: "CustomDependentOptionsBehaviorTest::TestAccount", 
              foreign_key: "firm_id", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    account = TestAccount.create!(name: "Test Account", firm_id: company.id)
    
    company.destroy
    
    # Verify account was processed
    account.reload
    assert_equal "ARCHIVED: Test Account", account.name
  end

  def test_belongs_to_individual_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestClient.class_eval do
      belongs_to :test_company, class_name: "CustomDependentOptionsBehaviorTest::TestCompany", 
                 foreign_key: "client_of", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    
    client.destroy
    
    # Verify company was processed
    company.reload
    assert_equal "ARCHIVED: Test Company", company.name
  end

  # Bulk Operation Tests
  def test_has_many_bulk_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk_archive, BulkArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :bulk_archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client1 = TestClient.create!(name: "Client 1", client_of: company.id)
    client2 = TestClient.create!(name: "Client 2", client_of: company.id)
    
    company.destroy
    
    # Verify clients were processed in bulk
    client1.reload
    client2.reload
    assert_equal "BULK: Client 1", client1.name
    assert_equal "BULK: Client 2", client2.name
  end

  def test_has_one_ignores_bulk_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk_archive, BulkArchiveHandler)
    
    TestCompany.class_eval do
      has_one :test_account, class_name: "CustomDependentOptionsBehaviorTest::TestAccount", 
              foreign_key: "firm_id", dependent: :bulk_archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    account = TestAccount.create!(name: "Test Account", firm_id: company.id)
    
    company.destroy
    
    # Verify account was processed individually (not bulk)
    account.reload
    assert_equal "INDIVIDUAL: Test Account", account.name
  end

  def test_belongs_to_ignores_bulk_processing
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk_archive, BulkArchiveHandler)
    
    TestClient.class_eval do
      belongs_to :test_company, class_name: "CustomDependentOptionsBehaviorTest::TestCompany", 
                 foreign_key: "client_of", dependent: :bulk_archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    
    client.destroy
    
    # Verify company was processed individually (not bulk)
    company.reload
    assert_equal "INDIVIDUAL: Test Company", company.name
  end

  def test_bulk_vs_individual_call_counts
    CountingHandler.reset_counts
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:counting, CountingHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :counting
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    TestClient.create!(name: "Client 1", client_of: company.id)
    TestClient.create!(name: "Client 2", client_of: company.id)
    TestClient.create!(name: "Client 3", client_of: company.id)
    
    company.destroy
    
    # Verify bulk method was called once, individual method was not called
    assert_equal 0, CountingHandler.call_count
    assert_equal 1, CountingHandler.bulk_call_count
  end

  def test_individual_processing_when_no_bulk_handler
    CountingHandler.reset_counts
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    TestClient.create!(name: "Client 1", client_of: company.id)
    TestClient.create!(name: "Client 2", client_of: company.id)
    
    company.destroy
    
    # Verify individual processing was used
    clients = TestClient.where(client_of: company.id)
    assert_equal 2, clients.count
    clients.each do |client|
      assert client.name.start_with?("ARCHIVED: ")
    end
  end

  # Block-based Handler Tests
  def test_block_based_handler_with_has_many
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:block_archive) do |record|
      record.update_columns(name: "BLOCK: #{record.name}")
    end
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :block_archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client1 = TestClient.create!(name: "Client 1", client_of: company.id)
    client2 = TestClient.create!(name: "Client 2", client_of: company.id)
    
    company.destroy
    
    # Verify clients were processed by block
    client1.reload
    client2.reload
    assert_equal "BLOCK: Client 1", client1.name
    assert_equal "BLOCK: Client 2", client2.name
  end

  def test_block_based_handler_with_has_one
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:block_archive) do |record|
      record.update_columns(name: "BLOCK: #{record.name}")
    end
    
    TestCompany.class_eval do
      has_one :test_account, class_name: "CustomDependentOptionsBehaviorTest::TestAccount", 
              foreign_key: "firm_id", dependent: :block_archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    account = TestAccount.create!(name: "Test Account", firm_id: company.id)
    
    company.destroy
    
    # Verify account was processed by block
    account.reload
    assert_equal "BLOCK: Test Account", account.name
  end

  def test_block_based_handler_with_belongs_to
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:block_archive) do |record|
      record.update_columns(name: "BLOCK: #{record.name}")
    end
    
    TestClient.class_eval do
      belongs_to :test_company, class_name: "CustomDependentOptionsBehaviorTest::TestCompany", 
                 foreign_key: "client_of", dependent: :block_archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    
    client.destroy
    
    # Verify company was processed by block
    company.reload
    assert_equal "BLOCK: Test Company", company.name
  end

  # Edge Case Tests
  def test_custom_dependent_option_with_nil_target
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_one :test_account, class_name: "CustomDependentOptionsBehaviorTest::TestAccount", 
              foreign_key: "firm_id", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    # No account created
    
    assert_nothing_raised do
      company.destroy
    end
  end

  def test_custom_dependent_option_with_empty_collection
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    # No clients created
    
    assert_nothing_raised do
      company.destroy
    end
  end

  def test_custom_dependent_option_with_loaded_association
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    
    # Load the association
    loaded_clients = company.test_clients.to_a
    assert_equal 1, loaded_clients.size
    
    company.destroy
    
    # Verify client was processed
    client.reload
    assert_equal "ARCHIVED: Test Client", client.name
  end

  def test_custom_dependent_option_with_unloaded_association
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    
    # Don't load the association
    company.destroy
    
    # Verify client was processed
    client.reload
    assert_equal "ARCHIVED: Test Client", client.name
  end

  # Callback Integration Tests
  def test_custom_dependent_option_with_callbacks
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:callback_trigger, CallbackTriggeringHandler)
    
    # Add a callback to track if it was called
    callback_called = false
    TestClient.class_eval do
      before_update do
        callback_called = true
      end
    end
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :callback_trigger
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    
    company.destroy
    
    # Verify callback was triggered
    assert callback_called, "Expected callback to be triggered"
    
    # Verify client was processed
    client.reload
    assert_equal "CALLBACK: Test Client", client.name
  end

  # Error Handling Tests
  def test_custom_dependent_option_error_handling
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:error_raising, ErrorRaisingHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :error_raising
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    
    # Should propagate the error from the handler
    assert_raises(RuntimeError, "Handler error for Test Client") do
      company.destroy
    end
  end

  # Performance Tests
  def test_bulk_operation_performance_benefit
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:bulk_archive, BulkArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :bulk_archive
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    
    # Create many clients
    100.times do |i|
      TestClient.create!(name: "Client #{i}", client_of: company.id)
    end
    
    # Measure SQL queries (this is a simplified test)
    query_count = 0
    original_execute = ActiveRecord::Base.connection.method(:execute)
    
    ActiveRecord::Base.connection.define_singleton_method(:execute) do |sql, *args|
      query_count += 1 if sql.include?("UPDATE")
      original_execute.call(sql, *args)
    end
    
    company.destroy
    
    # Restore original method
    ActiveRecord::Base.connection.define_singleton_method(:execute, original_execute)
    
    # Verify that bulk operation was used (should be 1 UPDATE query, not 100)
    assert query_count <= 2, "Expected bulk operation to use minimal queries, got #{query_count}"
  end

  # Integration Tests
  def test_multiple_associations_with_different_custom_dependent_options
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:soft_delete, SoftDeleteHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
      has_one :test_account, class_name: "CustomDependentOptionsBehaviorTest::TestAccount", 
              foreign_key: "firm_id", dependent: :soft_delete
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    client = TestClient.create!(name: "Test Client", client_of: company.id)
    account = TestAccount.create!(name: "Test Account", firm_id: company.id)
    
    company.destroy
    
    # Verify different handlers were used
    client.reload
    account.reload
    assert_equal "ARCHIVED: Test Client", client.name
    assert_equal "DELETED: Test Account", account.name
  end

  def test_custom_dependent_option_with_built_in_options
    ActiveRecord::Associations::Builder::Association.register_dependent_option(:archive, ArchiveHandler)
    
    TestCompany.class_eval do
      has_many :test_clients, class_name: "CustomDependentOptionsBehaviorTest::TestClient", 
               foreign_key: "client_of", dependent: :archive
      has_many :clients, dependent: :destroy  # Built-in option
    end
    
    company = TestCompany.create!(name: "Test Company", type: "Firm")
    test_client = TestClient.create!(name: "Test Client", client_of: company.id)
    regular_client = Client.create!(name: "Regular Client", client_of: company.id)
    
    company.destroy
    
    # Verify custom handler was used for test_clients
    test_client.reload
    assert_equal "ARCHIVED: Test Client", test_client.name
    
    # Verify regular client was destroyed (built-in :destroy)
    assert_nil Client.find_by(id: regular_client.id)
  end
end