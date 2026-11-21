require "digest"

module Rag
  module Evaluation
    class ReferenceDocument
      PATH = Rails.root.join("spec/fixtures/rag/evaluation/rag_evaluation_wildlife_reference.pdf").freeze

      def initialize(
        user:,
        path: PATH,
        embedding_configuration: Embeddings::Configuration.new,
        processor_class: Documents::Processor,
        embedding_generator: nil
      )
        @user = user
        @path = Pathname.new(path)
        @embedding_configuration = embedding_configuration
        @processor_class = processor_class
        @embedding_generator = embedding_generator || Embeddings::Generator.new(configuration: embedding_configuration)
      end

      def call
        raise ArgumentError, "An evaluation user is required" if @user.blank?
        raise ArgumentError, "Evaluation reference PDF not found: #{@path}" unless @path.file?

        document = find_or_create_document
        process_document(document) unless document.status == "completed" && document.document_chunks.exists?
        ensure_embeddings(document)
        document
      end

      private

      def find_or_create_document
        checksum = Digest::MD5.file(@path).base64digest
        existing = @user.documents.find_by(filename: @path.basename.to_s, checksum: checksum)
        return existing if existing

        document = @user.documents.build
        document.suppress_processing_enqueue = true
        File.open(@path, "rb") do |file|
          document.file.attach(
            io: file,
            filename: @path.basename.to_s,
            content_type: "application/pdf"
          )
          document.save!
        end
        document
      end

      def process_document(document)
        @processor_class.new(document).call
        document.reload
        unless document.status == "completed" && document.document_chunks.exists?
          raise "Evaluation reference document could not be processed: #{document.processing_error.presence || document.status}"
        end
      end

      def ensure_embeddings(document)
        chunks = document.document_chunks
        identity = @embedding_configuration.identity
        embeddings = DocumentChunkEmbedding
          .where(document_chunk_id: chunks.select(:id))
          .where(identity)
          .index_by(&:document_chunk_id)
        current = chunks.all? do |chunk|
          embeddings[chunk.id]&.current_for?(chunk.content)
        end

        @embedding_generator.call(chunks) unless current
        verify_embeddings!(chunks, identity)
      end

      def verify_embeddings!(chunks, identity)
        records = DocumentChunkEmbedding
          .where(document_chunk_id: chunks.select(:id))
          .where(identity)
          .index_by(&:document_chunk_id)
        incomplete = chunks.filter_map do |chunk|
          record = records[chunk.id]
          next if record&.current_for?(chunk.content)

          "#{chunk.id}: #{record&.error_message.presence || record&.status || 'missing'}"
        end
        return if incomplete.empty?

        raise "Evaluation reference embeddings are incomplete (#{incomplete.join('; ')})"
      end
    end
  end
end
