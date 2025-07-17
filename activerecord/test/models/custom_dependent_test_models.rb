# frozen_string_literal: true

# Test models for custom dependent options testing
# These models use existing tables but with different class names to avoid conflicts

class CustomDependentTestCompany < ActiveRecord::Base
  self.table_name = "companies"
  
  # Test associations with custom dependent options
  has_many :custom_dependent_test_clients, class_name: "CustomDependentTestClient", 
           foreign_key: "client_of", dependent: :destroy
  has_one :custom_dependent_test_account, class_name: "CustomDependentTestAccount", 
          foreign_key: "firm_id", dependent: :destroy
end

class CustomDependentTestClient < ActiveRecord::Base
  self.table_name = "clients"
  
  belongs_to :custom_dependent_test_company, class_name: "CustomDependentTestCompany", 
             foreign_key: "client_of", optional: true
end

class CustomDependentTestAccount < ActiveRecord::Base
  self.table_name = "accounts"
  
  belongs_to :custom_dependent_test_company, class_name: "CustomDependentTestCompany", 
             foreign_key: "firm_id", optional: true
end

# Test models for specific dependency scenarios
class ArchiveTestCompany < ActiveRecord::Base
  self.table_name = "companies"
end

class ArchiveTestClient < ActiveRecord::Base
  self.table_name = "clients"
end

class ArchiveTestAccount < ActiveRecord::Base
  self.table_name = "accounts"
end

class BulkTestCompany < ActiveRecord::Base
  self.table_name = "companies"
end

class BulkTestClient < ActiveRecord::Base
  self.table_name = "clients"
end

class SoftDeleteTestCompany < ActiveRecord::Base
  self.table_name = "companies"
end

class SoftDeleteTestClient < ActiveRecord::Base
  self.table_name = "clients"
end