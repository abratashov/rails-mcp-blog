require "test_helper"

class Rag::Strategies::ExhaustiveSearchTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @search = Rag::Strategies::ExhaustiveSearch.new
  end

  test "retrieves every chunk in source order without a semantic limit" do
    first = create_document(@user, "first document", status: "completed")
    second = create_document(@user, "second document", status: "completed")
    create_chunk(first, 1, "First chunk.", page_start: 1)
    create_chunk(first, 2, "Second chunk.", page_start: 2)
    create_chunk(second, 1, "Third chunk.")
    create_document(@user, "empty document", status: "completed")
    create_document(@user, "failed document", status: "failed", error: "Parser error")

    result = @search.call(
      "How many animal mentions?",
      user: @user,
      top_k: 1
    )

    assert_equal [ "First chunk.", "Second chunk.", "Third chunk." ], result.chunks.map(&:content)
    assert_equal [ 1, 2, 1 ], result.chunks.map(&:position)
    assert_equal 3, result.chunks.map(&:id).uniq.length
    assert_equal 4, result.document_count
    assert_equal "first document.txt", result.chunks.first.filename
    assert_equal 1, result.chunks.first.page_start
    assert_equal 1, result.incomplete_documents.length
    assert_equal "failed", result.incomplete_documents.first[:status]
  end

  test "respects the owner, selected document, and metadata filters" do
    owned = create_document(@user, "owned", status: "completed")
    other_owner = create_document(users(:two), "private", status: "completed")
    create_chunk(owned, 1, "Keep this.", metadata: { "section" => "wildlife" })
    create_chunk(owned, 2, "Exclude this.", metadata: { "section" => "history" })
    create_chunk(other_owner, 1, "Not visible.", metadata: { "section" => "wildlife" })

    result = @search.call(
      "Count wildlife topics",
      user: @user,
      document_id: owned.id,
      metadata: { "section" => "wildlife" }
    )

    assert_equal [ "Keep this." ], result.chunks.map(&:content)
    assert_equal 1, result.document_count
    assert_empty result.incomplete_documents

    unauthorized = @search.call("Count", user: @user, document_id: other_owner.id)
    assert_empty unauthorized.chunks
    assert_equal 0, unauthorized.document_count
  end

  private

  def create_document(user, contents, status:, error: nil)
    document = Document.new(user: user, status: status, processing_error: error)
    document.file.attach(io: StringIO.new(contents), filename: "#{contents}.txt", content_type: "text/plain")
    document.save!
    document
  end

  def create_chunk(document, position, content, page_start: nil, metadata: {})
    document.document_chunks.create!(
      position: position,
      content: content,
      page_start: page_start,
      metadata: metadata
    )
  end
end
