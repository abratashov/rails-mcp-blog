require "test_helper"

class Documents::ChunkerTest < ActiveSupport::TestCase
  test "keeps chunks within target size and preserves page and heading metadata" do
    chunker = Documents::Chunker.new(target_size: 40, overlap: 8)
    segments = [
      { content: "Section one", page_number: 1, metadata: { "kind" => "heading" } },
      { content: "First sentence. Second sentence.", page_number: 1, metadata: { "kind" => "paragraph" } },
      { content: "Це речення українською. Это русское предложение.", page_number: 2, metadata: { "kind" => "paragraph" } }
    ]

    chunks = chunker.call(segments)

    assert_operator chunks.length, :>, 1
    assert_equal (1..chunks.length).to_a, chunks.map { |chunk| chunk[:position] }
    assert chunks.all? { |chunk| chunk[:content].length <= 40 }
    assert_equal [ 1, 2 ], chunks.flat_map { |chunk| [ chunk[:page_start], chunk[:page_end] ] }.compact.uniq
    assert_equal [ "Section one" ], chunks.first.dig(:metadata, "headings")
  end

  test "overlaps adjacent chunks and splits oversized sentences at word boundaries" do
    chunker = Documents::Chunker.new(target_size: 24, overlap: 6)
    text = "One two three four five six seven eight nine ten."

    chunks = chunker.call([ { content: text, metadata: { "line_start" => 1 } } ])

    assert_operator chunks.length, :>, 1
    assert chunks.all? { |chunk| chunk[:content].length <= 24 }
    assert chunks.each_cons(2).any? { |left, right| left[:content].split.last == right[:content].split.first }
  end

  test "uses non-overlapping chunks by default" do
    chunker = Documents::Chunker.new(target_size: 24)
    text = "One two three four five six seven eight nine ten."

    chunks = chunker.call([ { content: text } ])

    assert_operator chunks.length, :>, 1
    reconstructed = chunks.map { |chunk| chunk[:content] }.join(" ")
    assert_equal text, reconstructed
  end

  test "validates size configuration" do
    assert_raises(ArgumentError) { Documents::Chunker.new(target_size: 0) }
    assert_raises(ArgumentError) { Documents::Chunker.new(target_size: 10, overlap: 10) }
    assert_raises(ArgumentError) { Documents::Chunker.new(target_size: 2, overlap: 1) }
  end
end
