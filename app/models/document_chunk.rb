class DocumentChunk < ApplicationRecord
  belongs_to :document

  validates :content, :position, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :position, uniqueness: { scope: :document_id }
  validates :page_start, :page_end, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[content created_at document_id page_end page_start position updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[document]
  end
end
