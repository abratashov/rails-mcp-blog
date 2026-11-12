require "digest"

class DocumentChunkEmbedding < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :document_chunk

  has_neighbors :embedding

  validates :provider, :model, :configuration_version, :input_checksum, presence: true
  validates :dimensions, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :embedding, presence: true, if: :completed?
  validates :embedding, absence: true, unless: :completed?
  validates :error_message, presence: true, if: :failed?

  validate :embedding_dimensions_match

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def current_for?(content)
    completed? && input_checksum == Digest::SHA256.hexdigest(content.to_s)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[configuration_version created_at dimensions document_chunk_id error_message model provider status updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[document_chunk]
  end

  private

  def embedding_dimensions_match
    return unless embedding.present?

    actual_dimensions = embedding.respond_to?(:dimensions) ? embedding.dimensions : embedding.length
    errors.add(:embedding, "must have #{dimensions} dimensions") if actual_dimensions != dimensions
  end
end
