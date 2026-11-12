class DocumentChunk < ApplicationRecord
  belongs_to :document
  has_many :document_chunk_embeddings, dependent: :destroy

  before_update :invalidate_embeddings, if: :will_save_change_to_content?
  after_update_commit :enqueue_embedding_regeneration, if: :saved_change_to_content?

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

  private

  def invalidate_embeddings
    document_chunk_embeddings.update_all(
      status: "pending",
      embedding: nil,
      error_message: nil,
      updated_at: Time.current
    )
  end

  def enqueue_embedding_regeneration
    GenerateDocumentEmbeddingsJob.perform_later(document_id, chunk_ids: [ id ])
  end
end
