module Documents
  class TextExtractor
    class ExtractionError < StandardError; end

    def initialize(pdf_reader: PDF::Reader)
      @pdf_reader = pdf_reader
    end

    def call(path, filename:)
      case File.extname(filename).downcase
      when ".pdf"
        extract_pdf(path)
      when ".docx"
        extract_docx(path)
      when ".txt"
        extract_txt(path)
      else
        raise ExtractionError, "Unsupported document format"
      end
    end

    private

    def extract_pdf(path)
      segments = @pdf_reader.new(path).pages.each_with_index.filter_map do |page, index|
        text = normalize(page.text)
        next if text.blank?

        { content: text, page_number: index + 1, metadata: { "kind" => "page" } }
      end

      ensure_content!(segments)
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::EncryptedPDFError => error
      raise ExtractionError, "Unable to read PDF: #{error.message}"
    end

    def extract_docx(path)
      segments = []

      Zip::File.open(path) do |zip|
        entry = zip.find_entry("word/document.xml")
        raise ExtractionError, "DOCX file is missing word/document.xml" unless entry

        xml = Nokogiri::XML(entry.get_input_stream.read) { |config| config.strict.nonet }
        xml.remove_namespaces!
        page_number = 1 if xml.xpath("//br[@type='page']").any?
        xml.xpath("//body/p").each_with_index do |paragraph, index|
          text = normalize(paragraph.xpath(".//t").map(&:text).join)
          page_breaks = paragraph.xpath(".//br[@type='page']").length
          unless text.blank?
            style = paragraph.at_xpath("./pPr/pStyle")&.[]("val")
            segments << {
              content: text,
              page_number: page_number,
              metadata: {
                "kind" => heading?(style) ? "heading" : "paragraph",
                "style" => style,
                "paragraph_index" => index + 1
              }.compact
            }
          end
          page_number += page_breaks if page_number && page_breaks.positive?
        end
      end

      ensure_content!(segments)
    rescue Zip::Error, Nokogiri::XML::SyntaxError => error
      raise ExtractionError, "Unable to read DOCX: #{error.message}"
    end

    def extract_txt(path)
      text = File.binread(path).force_encoding(Encoding::UTF_8).scrub
      lines = text.gsub(/\r\n?/, "\n").lines
      segments = []
      paragraph_lines = []
      line_start = nil

      lines.each_with_index do |line, index|
        if line.blank?
          if paragraph_lines.any?
            segments << txt_segment(paragraph_lines, line_start, index)
            paragraph_lines = []
            line_start = nil
          end
        else
          line_start ||= index + 1
          paragraph_lines << line
        end
      end
      segments << txt_segment(paragraph_lines, line_start, lines.length) if paragraph_lines.any?
      segments.each_with_index do |segment, index|
        next unless txt_heading?(segment[:content]) ||
                    (index < segments.length - 1 && segment[:content].lines.one? &&
                     segment[:content].length <= 100 && !segment[:content].match?(/[.!?。！？]\z/))

        segment[:metadata]["kind"] = "heading"
      end

      ensure_content!(segments)
    end

    def normalize(text)
      text.to_s.gsub(/\r\n?/, "\n").gsub(/[ \t]+/, " ").strip
    end

    def ensure_content!(segments)
      raise ExtractionError, "Document contains no extractable text" if segments.empty?

      segments
    end

    def heading?(style)
      style.to_s.match?(/\A(?:title|subtitle|heading\d*)\z/i)
    end

    def txt_segment(lines, line_start, line_end)
      {
        content: normalize(lines.join),
        metadata: {
          "kind" => "paragraph",
          "line_start" => line_start,
          "line_end" => line_end
        }
      }
    end

    def txt_heading?(text)
      text.match?(/\A(?:\#{1,6}\s+|\d+(?:\.\d+)*[.)]?\s+)/)
    end
  end
end
