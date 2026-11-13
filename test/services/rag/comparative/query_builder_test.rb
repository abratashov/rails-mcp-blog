require "test_helper"

class Rag::Comparative::QueryBuilderTest < ActiveSupport::TestCase
  test "builds a separate query for each subject and ignores document-scope wording" do
    queries = Rag::Comparative::QueryBuilder.new.call(
      "Compare lions and tigers across all uploaded documents."
    )

    assert_equal [ "lions", "tigers" ], queries.map(&:subject)
    assert_equal [ "lions", "tigers" ], queries.map(&:text)
  end

  test "includes explicitly requested comparison aspects in each subject query" do
    queries = Rag::Comparative::QueryBuilder.new.call(
      "Compare lions and tigers in terms of diet and habitat."
    )

    assert_equal [ "diet and habitat", "diet and habitat" ], queries.map(&:aspect)
    assert_equal [ "lions diet and habitat", "tigers diet and habitat" ], queries.map(&:text)
  end

  test "falls back to the original question when subjects cannot be safely extracted" do
    queries = Rag::Comparative::QueryBuilder.new.call("Analyze these documents.")

    assert_equal 1, queries.length
    assert_nil queries.first.subject
    assert_equal "Analyze these documents.", queries.first.text
  end
end
