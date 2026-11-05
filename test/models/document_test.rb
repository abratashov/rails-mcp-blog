require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
  end

  test "copies attachment metadata and starts pending" do
    document = build_document("Hello, world.")

    assert document.valid?, document.errors.full_messages.join(", ")
    assert_equal "sample.txt", document.filename
    assert_equal "text/plain", document.content_type
    assert_equal "Hello, world.".bytesize, document.file_size
    assert_predicate document.checksum, :present?
    assert_equal "pending", document.status
  end

  test "enqueues processing after an upload is committed" do
    assert_enqueued_with(job: ProcessDocumentJob) do
      build_document("Hello, world.").save!
    end
  end

  test "requires a file and rejects unsupported formats" do
    assert_not Document.new(user: @user).valid?

    document = Document.new(user: @user)
    document.file.attach(io: StringIO.new("data"), filename: "sample.exe", content_type: "application/octet-stream")
    assert_not document.valid?
    assert_includes document.errors[:file], "must be a PDF, DOCX, or TXT document"
  end

  test "prevents duplicate uploads per owner but allows other owners" do
    existing = build_document("same contents")
    existing.save!

    duplicate = build_document("same contents")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:checksum], "has already been taken"

    other_owner = build_document("same contents", user: users(:two))
    assert other_owner.valid?, other_owner.errors.full_messages.join(", ")
  end

  test "rejects a file that exceeds the maximum size" do
    document = build_document("small")
    document.save!
    document.file_size = Document::MAX_FILE_SIZE + 1

    assert_not document.valid?
    assert_includes document.errors[:file], "must be no larger than 50 MB"
  end

  private

  def build_document(contents, user: @user)
    document = Document.new(user: user)
    document.file.attach(
      io: StringIO.new(contents),
      filename: "sample.txt",
      content_type: "text/plain"
    )
    document
  end
end
