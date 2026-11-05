module Documents
  class Processor
    def initialize(document, extractor: TextExtractor.new, chunker: Chunker.new)
      @document = document
      @extractor = extractor
      @chunker = chunker
    end

    def call
      @document.with_lock do
        @document.update!(status: "processing", processing_error: nil)

        @document.file.open do |file|
          segments = @extractor.call(file.path, filename: @document.filename)
          chunks = @chunker.call(segments)

          @document.document_chunks.delete_all
          chunks.each do |attributes|
            @document.document_chunks.create!(attributes)
          end
        end

        @document.update!(status: "completed", processing_error: nil)
      end
    rescue StandardError => error
      @document.update!(
        status: "failed",
        processing_error: "#{error.class}: #{error.message}".truncate(10_000)
      )
      raise
    end
  end
end
