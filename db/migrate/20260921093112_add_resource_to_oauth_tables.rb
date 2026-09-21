class AddResourceToOauthTables < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_access_grants, :resource, :string
    add_column :oauth_access_tokens, :resource, :string
    add_index :oauth_access_tokens, :resource
  end
end
