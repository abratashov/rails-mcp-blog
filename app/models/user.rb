class User < ApplicationRecord
  has_many :access_grants,
           class_name: "Doorkeeper::AccessGrant",
           foreign_key: :resource_owner_id,
           dependent: :delete_all

  has_many :access_tokens,
           class_name: "Doorkeeper::AccessToken",
           foreign_key: :resource_owner_id,
           dependent: :delete_all
  has_many :documents, dependent: :destroy
  has_many :rag_conversations, dependent: :destroy

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  def self.ransackable_attributes(_auth_object = nil)
    %w[email id]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  alias_attribute :title, :email
end
