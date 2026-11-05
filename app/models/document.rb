class Document < ApplicationRecord
  MAX_FILE_SIZE = 50.megabytes
  SUPPORTED_FORMATS = {
    ".pdf" => [ "application/pdf" ],
    ".docx" => [
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "application/zip"
    ],
    ".txt" => [ "text/plain" ]
  }.freeze
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :user
  has_one_attached :file, dependent: :purge_later
  has_many :document_chunks, -> { order(:position) }, dependent: :destroy

  before_validation :copy_file_metadata, if: -> { attachment_changes.key?("file") }
  after_create_commit :enqueue_processing

  validates :filename, :content_type, :file_size, :checksum, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :checksum, uniqueness: { scope: :user_id }
  validate :file_is_attached
  validate :file_format_is_supported
  validate :file_size_is_reasonable

  alias_attribute :title, :filename

  def self.ransackable_attributes(_auth_object = nil)
    %w[checksum content_type created_at file_size filename status updated_at user_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[document_chunks user]
  end

  private

  def copy_file_metadata
    return unless file.attached?

    self.filename = file.blob.filename.to_s
    self.content_type = file.blob.content_type
    self.file_size = file.blob.byte_size
    self.checksum = file.blob.checksum
  end

  def file_is_attached
    errors.add(:file, :blank) unless file.attached?
  end

  def file_format_is_supported
    return unless file.attached?

    extension = File.extname(filename.to_s).downcase
    accepted_content_types = SUPPORTED_FORMATS[extension]

    if accepted_content_types.nil? || !accepted_content_types.include?(content_type)
      errors.add(:file, "must be a PDF, DOCX, or TXT document")
    end
  end

  def file_size_is_reasonable
    return if file_size.nil? || file_size <= MAX_FILE_SIZE

    errors.add(:file, "must be no larger than #{MAX_FILE_SIZE / 1.megabyte} MB")
  end

  def enqueue_processing
    ProcessDocumentJob.perform_later(self)
  end
end
