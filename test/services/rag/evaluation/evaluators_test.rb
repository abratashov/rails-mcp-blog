require "test_helper"

class RagEvaluationEvaluatorsTest < ActiveSupport::TestCase
  Chunk = Struct.new(:id, :filename, :position, :content, :score, keyword_init: true)

  test "scores required terms and recognizes insufficient evidence in multiple scripts" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    complete = evaluator.call(
      { "expected_term_groups" => [ %w[lion lions], %w[pride prides] ] },
      result(answer: "<think>lion is wrong</think>Lions live in prides.")
    )
    insufficient = evaluator.call(
      { "insufficient_evidence" => true },
      result(answer: "I couldn't find enough relevant information.", grounded: false, chunks: [])
    )
    irrelevant_context = evaluator.call(
      { "insufficient_evidence" => true },
      result(
        answer: "The provided documents do not mention penguins.",
        grounded: true,
        chunks: [ Chunk.new(id: 5, filename: "animals.txt", content: "Lions live in prides.") ]
      )
    )
    ukrainian_insufficient = evaluator.call(
      { "insufficient_evidence" => true, "language" => "ua" },
      result(answer: "У документі не вказано, чим харчуються пінгвіни.")
    )

    assert_equal 1.0, complete[:completeness]
    assert_equal 1.0, complete[:correctness]
    assert_equal %w[lion pride], complete[:matched_terms]
    assert_equal 1.0, insufficient[:correctness]
    assert insufficient[:insufficient_evidence_correct]
    assert_equal 1.0, irrelevant_context[:correctness]
    assert_equal 1.0, ukrainian_insufficient[:correctness]
  end

  test "measures retrieval coverage, relevance, citation accuracy, and faithfulness" do
    chunk = Chunk.new(id: 5, filename: "animals.txt", position: 1, content: "Lions live in prides.", score: 0.9)
    citation = { source_chunk_id: 5, content: chunk.content }
    metrics = Rag::Evaluation::RetrievalEvaluator.new.call(
      {
        "relevant_source_chunks" => [ { "content_contains" => "Lions live in prides." } ],
        "expected_term_groups" => [ %w[lion lions], %w[pride prides] ],
        "gold_relations" => [
          {
            "evidence_groups" => [ %w[lion lions], [ "live in" ], %w[pride prides] ]
          }
        ]
      },
      result(answer: "Lions live in prides.", chunks: [ chunk ], citations: [ citation ])
    )

    assert_equal 1.0, metrics[:relevance]
    assert_equal 1.0, metrics[:coverage]
    assert_equal 1.0, metrics[:citation_accuracy]
    assert_equal 1.0, metrics[:faithfulness]
    assert_equal 1.0, metrics[:citation_relevance]
    assert_equal 1.0, metrics[:claim_support]
    assert_equal 1, metrics[:claims_supported]
  end

  test "does not count irrelevant citations as relevant for insufficient-evidence questions" do
    chunk = Chunk.new(id: 5, filename: "animals.txt", position: 1, content: "Lions live in prides.", score: 0.9)
    metrics = Rag::Evaluation::RetrievalEvaluator.new.call(
      { "insufficient_evidence" => true, "relevant_source_chunks" => [] },
      result(
        answer: "The document does not mention penguins.",
        chunks: [ chunk ],
        citations: [ { source_chunk_id: 5, content: chunk.content } ]
      )
    )

    assert_equal 1.0, metrics[:coverage]
    assert_equal 1.0, metrics[:citation_accuracy]
    assert_equal 0.0, metrics[:citation_relevance]
  end

  test "does not combine evidence from separate citations to support a claim" do
    metrics = Rag::Evaluation::RetrievalEvaluator.new.call(
      {
        "gold_relations" => [
          { "evidence_groups" => [ %w[lion lions], [ "live in" ], %w[pride prides] ] }
        ]
      },
      result(
        answer: "Lions live in prides.",
        citations: [
          { content: "Lions live in groups." },
          { content: "Their groups are called prides." }
        ]
      )
    )

    assert_equal 0.0, metrics[:claim_support]
    assert_equal 0, metrics[:claims_supported]
  end

  test "citation relevance recognizes claim-supporting chunks and rejects unrelated citations" do
    metrics = Rag::Evaluation::RetrievalEvaluator.new.call(
      {
        "relevant_source_chunks" => [ { "content_contains" => "different reference excerpt" } ],
        "gold_relations" => [
          {
            "subject" => "lion",
            "object" => "pride",
            "evidence_groups" => [ %w[lion lions], [ "called" ], %w[pride prides] ]
          }
        ]
      },
      result(
        answer: "The lion's social unit is called a pride.",
        citations: [
          { source_chunk_id: 1, content: "Their basic social unit is called a pride for lions." },
          { source_chunk_id: 2, content: "Tigers inhabit forests and wetlands." }
        ]
      )
    )

    assert_equal 1, metrics[:citations_relevant]
    assert_equal 0.5, metrics[:citation_relevance]
    assert_equal 1.0, metrics[:claim_support]
  end

  test "aggregation citation relevance recognizes citations supporting expected entities" do
    metrics = Rag::Evaluation::RetrievalEvaluator.new.call(
      {
        "type" => "aggregation",
        "relevant_source_chunks" => [],
        "evidence_term_groups" => [ %w[lion lions], %w[tiger tigers] ]
      },
      result(
        answer: "Two species are described.",
        citations: [
          { source_chunk_id: 1, content: "Lions live in prides." },
          { source_chunk_id: 2, content: "Penguins feed on fish." }
        ]
      )
    )

    assert_equal 1, metrics[:citations_relevant]
    assert_equal 0.5, metrics[:citation_relevance]
  end

  test "requires expected answer language and accepts explicit multilingual concept variants" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    ukrainian = evaluator.call(
      {
        "language" => "ua",
        "expected_term_groups" => [ %w[леви], %w[прайд прайдами] ]
      },
      result(answer: "Леви живуть прайдами.")
    )
    wrong_language = evaluator.call(
      {
        "language" => "ua",
        "expected_term_groups" => [ %w[леви], %w[прайд прайдами] ]
      },
      result(answer: "Lions live in prides.")
    )

    assert_equal 1.0, ukrainian[:correctness]
    assert_equal 1.0, ukrainian[:language_match]
    assert_equal 0.0, wrong_language[:correctness]
    assert_equal 0.0, wrong_language[:language_match]
  end

  private

  def result(answer:, grounded: true, chunks: [], citations: [])
    Rag::Result.new(answer: answer, grounded: grounded, retrieved_chunks: chunks, citations: citations)
  end

  test "detects incorrect multilingual entity names and missing gold concepts" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    question = {
      "language" => "ru",
      "expected_term_groups" => [ %w[лисица лиса], %w[рысь] ],
      "gold_concepts" => [
        { "id" => "red_fox", "aliases" => %w[лисица лиса], "incorrect_aliases" => [ "красная кошка" ] },
        { "id" => "lynx", "aliases" => [ "рысь" ] }
      ]
    }

    metrics = evaluator.call(question, result(answer: "В справочнике описана красная кошка."))

    assert_equal [ "red_fox", "lynx" ], metrics.dig(:concepts, :missing)
    assert_equal [ { concept: "red_fox", term: "красная кошка" } ], metrics.dig(:concepts, :incorrect)
    assert_equal 0.0, metrics[:concept_coverage]
  end

  test "scores aggregation answers by the requested count and keeps entity checks separate" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    question = {
      "type" => "aggregation",
      "answer_term_groups" => [ %w[шесть 6] ],
      "expected_term_groups" => [ %w[шесть 6], %w[лев львы], %w[тигр тигры] ],
      "gold_concepts" => [
        { "id" => "lion", "aliases" => %w[лев львы] },
        { "id" => "tiger", "aliases" => %w[тигр тигры] }
      ]
    }

    metrics = evaluator.call(question, result(answer: "В справочнике описано 6 видов млекопитающих."))

    assert_equal 1.0, metrics[:correctness]
    assert_equal 1.0, metrics[:completeness]
    assert_equal 1.0, metrics[:concept_coverage]
    assert_equal 0, metrics.dig(:concepts, :total)
  end

  test "checks subject-fact attribution within each answer clause" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    question = {
      "gold_concepts" => [
        { "id" => "lion", "aliases" => [ "lions" ] },
        { "id" => "pride", "aliases" => [ "prides" ] },
        { "id" => "tiger", "aliases" => [ "tigers" ] },
        { "id" => "solitary", "aliases" => [ "solitary" ] }
      ],
      "gold_relations" => [
        { "subject" => "lion", "predicate_aliases" => [ "live in" ], "object" => "pride" },
        { "subject" => "tiger", "predicate_aliases" => [ "are" ], "object" => "solitary" }
      ]
    }

    correct = evaluator.call(question, result(answer: "Lions live in prides, while tigers are solitary."))
    swapped = evaluator.call(question, result(answer: "Lions are solitary, while tigers live in prides."))

    assert_equal 1.0, correct.dig(:relations, :recall)
    assert_equal 0.0, swapped.dig(:relations, :recall)
    assert_equal 0.0, swapped[:correctness]
  end

  test "matches a later predicate alias when an earlier alias appears before the subject" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    question = {
      "gold_concepts" => [
        { "id" => "lion", "aliases" => [ "lions" ] },
        { "id" => "pride", "aliases" => [ "pride" ] }
      ],
      "gold_relations" => [
        { "subject" => "lion", "predicate_aliases" => [ "social unit", "called" ], "object" => "pride" }
      ]
    }

    metrics = evaluator.call(
      question,
      result(answer: "The basic social unit of lions is called a pride.")
    )

    assert_equal 1.0, metrics.dig(:relations, :recall)
    assert_equal 1.0, metrics[:correctness]
  end

  test "accepts Russian adverbial form of solitary behavior" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    question = {
      "language" => "ru",
      "expected_term_groups" => [ %w[тигр тигры], %w[одиноч поодиноч] ],
      "gold_concepts" => [
        { "id" => "tiger", "aliases" => %w[тигр тигры] },
        { "id" => "solitary", "aliases" => %w[одиночка одиночку одиночно поодиночке] }
      ],
      "gold_relations" => [
        { "subject" => "tiger", "predicate_aliases" => %w[живут обычно], "object" => "solitary" }
      ]
    }

    metrics = evaluator.call(
      question,
      result(answer: "Взрослые тигры обычно живут одиночно.")
    )

    assert_equal 1.0, metrics.dig(:concepts, :recall)
    assert_equal 1.0, metrics.dig(:relations, :recall)
    assert_equal 1.0, metrics[:correctness]
  end

  test "accepts Russian loanword phrase for solitary behavior" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    question = {
      "language" => "ru",
      "expected_term_groups" => [ %w[тигр тигры], [ "одиноч", "поодиноч", "солитарный образ жизни" ] ],
      "gold_concepts" => [
        { "id" => "tiger", "aliases" => %w[тигр тигры] },
        { "id" => "solitary", "aliases" => [ "одиночка", "одиночно", "поодиночке", "солитарный образ жизни" ] }
      ],
      "gold_relations" => [
        { "subject" => "tiger", "predicate_aliases" => [ "обычно", "ведут" ], "object" => "solitary" }
      ]
    }

    metrics = evaluator.call(
      question,
      result(answer: "Взрослые тигры обычно ведут солитарный образ жизни.")
    )

    assert_equal 1.0, metrics.dig(:concepts, :recall)
    assert_equal 1.0, metrics.dig(:relations, :recall)
    assert_equal 1.0, metrics[:correctness]
  end

  test "keeps comma-separated evidence attached to its subject" do
    evaluator = Rag::Evaluation::AnswerEvaluator.new
    question = {
      "gold_concepts" => [
        { "id" => "tiger", "aliases" => [ "tigers" ] },
        { "id" => "forest", "aliases" => [ "forests" ] },
        { "id" => "wetland", "aliases" => [ "wetlands" ] }
      ],
      "gold_relations" => [
        { "subject" => "tiger", "predicate_aliases" => [ "inhabit" ], "object" => "forest" },
        { "subject" => "tiger", "predicate_aliases" => [ "inhabit" ], "object" => "wetland" }
      ]
    }

    metrics = evaluator.call(
      question,
      result(answer: "Tigers inhabit a variety of environments, including tropical forests, wetlands, and grasslands.")
    )

    assert_equal 1.0, metrics.dig(:relations, :recall)
  end

  test "scores cited evidence using source-language terms for multilingual questions" do
    metrics = Rag::Evaluation::RetrievalEvaluator.new.call(
      {
        "expected_term_groups" => [ %w[тигр], %w[одиночку] ],
        "evidence_term_groups" => [ %w[tigers], %w[solitary] ]
      },
      result(answer: "Тигры обычно живут в одиночку.", citations: [ { content: "Tigers are generally solitary." } ])
    )

    assert_equal 1.0, metrics[:faithfulness]
  end
end
