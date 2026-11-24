require "test_helper"

class Rag::Strategies::ComparativeSearchTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @fallback = FakeRetriever.new
    @search = Rag::Strategies::ComparativeSearch.new(
      fallback: @fallback,
      top_k: 4
    )
  end

  test "queries each subject independently with comparative limits and existing scope filters" do
    result = @search.call(
      "Compare lions and tigers",
      user: @user,
      document_id: 12,
      metadata: { "section" => "wildlife" },
      top_k: 9
    )

    assert_equal [ "lions", "tigers" ], @fallback.calls.map { |call| call[:question] }
    assert @fallback.calls.all? { |call| call[:top_k] == 4 }
    assert @fallback.calls.all? { |call| call[:user] == @user }
    assert @fallback.calls.all? { |call| call[:document_id] == 12 }
    assert @fallback.calls.all? { |call| call[:metadata] == { "section" => "wildlife" } }
    assert_equal [ "lions", "tigers" ], result.queries.map { |query| query[:subject] }
    assert_equal [ 1, 2 ], result.chunks.map { |chunk| chunk[:position] }
  end

  test "validates the independent comparative Top-K setting" do
    assert_raises(ArgumentError) do
      Rag::Strategies::ComparativeSearch.new(fallback: @fallback, top_k: 0)
    end
  end

  class FakeRetriever
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(question, **options)
      @calls << options.merge(question: question)
      position = question == "lions" ? 1 : 2
      [ Rag::Retrieval::Result.new(
        document_id: 5,
        filename: "animals.txt",
        position: position,
        content: "#{question} evidence",
        score: 0.9,
        metadata: {}
      ) ]
    end
  end
end
