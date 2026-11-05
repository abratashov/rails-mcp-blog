require "test_helper"
require "tmpdir"

class Documents::TextExtractorTest < ActiveSupport::TestCase
  FakePdfReader = Class.new do
    def self.new(_path)
      page = Struct.new(:text)
      Struct.new(:pages).new([ page.new("Page one"), page.new("Page two") ])
    end
  end

  setup do
    @extractor = Documents::TextExtractor.new
  end

  test "extracts multilingual TXT paragraphs and line positions" do
    with_file("Title\n\nHello world.\nДругий рядок.\n\n\nПривет мир.", "sample.txt") do |path|
      segments = @extractor.call(path, filename: "sample.txt")

      assert_equal [ "Title", "Hello world.\nДругий рядок.", "Привет мир." ], segments.map { |segment| segment[:content] }
      assert_equal "heading", segments.first.dig(:metadata, "kind")
      assert_equal 3, segments.second.dig(:metadata, "line_start")
      assert_equal 4, segments.second.dig(:metadata, "line_end")
      assert_equal 7, segments.third.dig(:metadata, "line_start")
    end
  end

  test "extracts DOCX paragraphs and headings without inventing pagination" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
          <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Заголовок</w:t></w:r></w:p>
          <w:p><w:r><w:t>English paragraph.</w:t></w:r></w:p>
        </w:body>
      </w:document>
    XML

    with_docx(xml) do |path|
      segments = @extractor.call(path, filename: "sample.docx")

      assert_equal [ "Заголовок", "English paragraph." ], segments.map { |segment| segment[:content] }
      assert_equal "heading", segments.first.dig(:metadata, "kind")
      assert_equal 2, segments.second.dig(:metadata, "paragraph_index")
      assert_nil segments.first[:page_number]
    end
  end

  test "uses explicit DOCX page breaks when present" do
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
          <w:p><w:r><w:t>First page</w:t><w:br w:type="page"/></w:r></w:p>
          <w:p><w:r><w:t>Second page</w:t></w:r></w:p>
        </w:body>
      </w:document>
    XML

    with_docx(xml) do |path|
      segments = @extractor.call(path, filename: "sample.docx")

      assert_equal [ 1, 2 ], segments.map { |segment| segment[:page_number] }
    end
  end

  test "preserves PDF page numbers" do
    extractor = Documents::TextExtractor.new(pdf_reader: FakePdfReader)
    with_file("not used", "sample.pdf") do |path|
      segments = extractor.call(path, filename: "sample.pdf")

      assert_equal [ 1, 2 ], segments.map { |segment| segment[:page_number] }
      assert_equal [ "Page one", "Page two" ], segments.map { |segment| segment[:content] }
    end
  end

  test "raises a clear extraction error for empty documents and unsupported types" do
    with_file(" \n ", "empty.txt") do |path|
      error = assert_raises(Documents::TextExtractor::ExtractionError) do
        @extractor.call(path, filename: "empty.txt")
      end
      assert_match "no extractable text", error.message
    end

    error = assert_raises(Documents::TextExtractor::ExtractionError) do
      @extractor.call("unused", filename: "sample.rtf")
    end
    assert_match "Unsupported", error.message
  end

  test "reports a corrupt DOCX archive" do
    with_file("not a zip file", "sample.docx") do |path|
      assert_raises(Documents::TextExtractor::ExtractionError) do
        @extractor.call(path, filename: "sample.docx")
      end
    end
  end

  private

  def with_file(contents, filename)
    Dir.mktmpdir do |directory|
      path = File.join(directory, filename)
      File.binwrite(path, contents)
      yield path
    end
  end

  def with_docx(xml)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "sample.docx")
      Zip::OutputStream.open(path) do |zip|
        zip.put_next_entry("word/document.xml")
        zip.write(xml)
      end
      yield path
    end
  end
end
