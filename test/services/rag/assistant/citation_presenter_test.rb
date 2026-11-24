require "test_helper"

class Rag::Assistant::CitationPresenterTest < ActiveSupport::TestCase
  test "builds and decorates citations with page references" do
    item = Struct.new(
      :source_id, :source_chunk_id, :document_id, :filename, :page_start, :page_end,
      :position, :content, :score, :distance
    ).new("source-1", "chunk-1", 7, "guide.txt", 2, 3, 1, "Evidence", 0.9, 0.1)
    presenter = Rag::Assistant::CitationPresenter.new

    citations = presenter.build_citations([ item ])
    answer = presenter.decorate_with_citations("Supported answer [1].", citations)

    assert_equal 1, citations.first[:label]
    assert_equal "chunk-1", citations.first[:source_chunk_id]
    assert_includes answer, "[1] guide.txt (p. 2-3)"
  end

  test "keeps only referenced citations and suppresses citations for insufficient evidence" do
    citations = [
      { label: 1, filename: "first.txt" },
      { label: 2, filename: "second.txt" }
    ]
    presenter = Rag::Assistant::CitationPresenter.new

    assert_equal [ citations.last ], presenter.citations_used_by("Supported by [2].", citations)
    [
      "There is insufficient evidence.",
      "No information is available.",
      "Нет информации."
    ].each do |answer|
      assert_empty presenter.citations_used_by(answer, citations)
    end
  end
end
