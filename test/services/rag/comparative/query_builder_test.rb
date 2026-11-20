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

  test "builds independent queries for Ukrainian comparisons" do
    queries = Rag::Comparative::QueryBuilder.new.call("Порівняй левів і тигрів")

    assert_equal [ "левів", "тигрів" ], queries.map(&:subject)
    assert_equal [ "левів", "тигрів" ], queries.map(&:text)
  end

  test "builds independent queries for Ukrainian between-comparisons with aspects" do
    queries = Rag::Comparative::QueryBuilder.new.call(
      "Які відмінності між левами та тиграми за середовищем існування?"
    )

    assert_equal [ "левами", "тиграми" ], queries.map(&:subject)
    assert_equal [ "середовищем існування", "середовищем існування" ], queries.map(&:aspect)
    assert_equal [
      "левами середовищем існування",
      "тиграми середовищем існування"
    ], queries.map(&:text)
  end

  test "builds independent queries for Russian comparisons" do
    queries = Rag::Comparative::QueryBuilder.new.call("Сравни львов и тигров")

    assert_equal [ "львов", "тигров" ], queries.map(&:subject)
    assert_equal [ "львов", "тигров" ], queries.map(&:text)
  end

  test "builds independent queries for Russian between-comparisons" do
    queries = Rag::Comparative::QueryBuilder.new.call(
      "В чем разница между львами и тиграми?"
    )

    assert_equal [ "львами", "тиграми" ], queries.map(&:subject)
    assert_equal [ "львами", "тиграми" ], queries.map(&:text)
  end

  test "falls back to the original question when subjects cannot be safely extracted" do
    queries = Rag::Comparative::QueryBuilder.new.call("Analyze these documents.")

    assert_equal 1, queries.length
    assert_nil queries.first.subject
    assert_equal "Analyze these documents.", queries.first.text
  end
end
