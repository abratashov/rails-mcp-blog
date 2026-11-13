require "test_helper"

class RagRetrievalRouterTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @semantic = FakeStrategy.new(:semantic)
    @comparative = FakeStrategy.new(:comparative)
    @exhaustive = FakeStrategy.new(:exhaustive)
    @router = Rag::RetrievalRouter.new(
      semantic_search: @semantic,
      comparative_search: @comparative,
      exhaustive_search: @exhaustive
    )
  end

  test "routes specific questions to semantic top-k" do
    result = @router.call("What do lions eat?", question_type: "specific", user: @user)

    assert_equal :semantic, result.chunks
    assert_equal "semantic_top_k", result.strategy
  end

  test "routes comparative questions to multi-chunk retrieval" do
    result = @router.call("Compare lions and tigers", question_type: "comparative", user: @user)

    assert_equal :comparative, result.chunks
    assert_equal "multi_chunk", result.strategy
  end

  test "returns comparative retrieval queries alongside the chunks" do
    query = { subject: "lions", aspect: nil, text: "lions" }
    @comparative = FakeQueryStrategy.new(:comparative, [ query ])
    @router = Rag::RetrievalRouter.new(
      semantic_search: @semantic,
      comparative_search: @comparative,
      exhaustive_search: @exhaustive
    )

    result = @router.call("Compare lions and tigers", question_type: "comparative", user: @user)

    assert_equal :comparative, result.chunks
    assert_equal [ query ], result.retrieval_queries
  end

  test "routes aggregation questions to exhaustive retrieval" do
    result = @router.call("How many species are mentioned?", question_type: "aggregation", user: @user)

    assert_equal :exhaustive, result.chunks
    assert_equal "exhaustive", result.strategy
  end

  test "preserves document scope and metadata when routing" do
    @router.call(
      "Compare lions and tigers",
      question_type: "comparative",
      user: @user,
      document_id: 17,
      metadata: { "section" => "wildlife" },
      top_k: 8
    )

    assert_equal @user, @comparative.options[:user]
    assert_equal 17, @comparative.options[:document_id]
    assert_equal({ "section" => "wildlife" }, @comparative.options[:metadata])
    assert_equal 8, @comparative.options[:top_k]
  end

  class FakeStrategy
    attr_reader :options

    def initialize(result)
      @result = result
    end

    def call(question, **options)
      @options = options.merge(question: question)
      @result
    end

  end

  class FakeQueryStrategy < FakeStrategy
    def initialize(result, queries)
      super(result)
      @queries = queries
    end

    def call(question, **options)
      super
      Struct.new(:chunks, :queries).new(@result, @queries)
    end
  end
end
