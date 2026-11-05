require "test_helper"

class Documents::ProcessorTest < ActiveSupport::TestCase
  test "persists chunks atomically and can safely process a document again" do
    document = create_document(("This is an English paragraph. Це український абзац. " * 60).strip)

    2.times { ProcessDocumentJob.perform_now(document) }

    assert_equal "completed", document.reload.status
    assert_nil document.processing_error
    positions = document.document_chunks.pluck(:position)
    assert_operator positions.length, :>, 1
    assert_equal (1..positions.length).to_a, positions
    assert_includes document.document_chunks.pluck(:content).join(" "), "український"
  end

  test "records extraction errors without keeping partial chunks" do
    document = create_document(" ")

    assert_raises(Documents::TextExtractor::ExtractionError) do
      Documents::Processor.new(document).call
    end

    assert_equal "failed", document.reload.status
    assert_match "no extractable text", document.processing_error
    assert_empty document.document_chunks
  end

  private

  def create_document(contents)
    document = Document.new(user: users(:one))
    document.file.attach(
      io: StringIO.new(contents),
      filename: "sample.txt",
      content_type: "text/plain"
    )
    document.save!
    document
  end
end
