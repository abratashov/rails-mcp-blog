require "cgi"

module Rag
  module Analysis
    class BatchProcessor
      BatchFailure = Struct.new(:batch, :chunk_ids, :attempts, :error, keyword_init: true)
      Result = Struct.new(
        :entities,
        :facts,
        :failed_batches,
        :processed_batches,
        :total_batches,
        keyword_init: true
      )

      PROMPT_OVERHEAD_TOKENS = 500
      CONTEXT_WINDOW_SAFETY_TOKENS = 256
      DEFAULT_BATCH_SIZE = 8
      DEFAULT_MAX_INPUT_TOKENS = 1_800
      DEFAULT_CONTEXT_WINDOW = 4_096

      attr_reader :max_input_tokens

      def initialize(
        extractor: EntityExtractor.new,
        batch_size: ENV.fetch("RAG_ANALYSIS_BATCH_SIZE", DEFAULT_BATCH_SIZE),
        max_input_tokens: ENV.fetch("RAG_ANALYSIS_MAX_INPUT_TOKENS", DEFAULT_MAX_INPUT_TOKENS),
        max_output_tokens: ENV.fetch("RAG_ANALYSIS_EXTRACTION_MAX_TOKENS", "2_000"),
        context_window: ENV.fetch("RAG_ANALYSIS_CONTEXT_WINDOW", DEFAULT_CONTEXT_WINDOW),
        max_retries: ENV.fetch("RAG_ANALYSIS_MAX_RETRIES", "2"),
        retry_delay: ENV.fetch("RAG_ANALYSIS_RETRY_DELAY", "0.1"),
        sleeper: ->(seconds) { sleep(seconds) }
      )
        @extractor = extractor
        @batch_size = positive_integer(batch_size, "Analysis batch size")
        requested_input_tokens = positive_integer(max_input_tokens, "Analysis input token limit")
        @max_input_tokens = self.class.effective_input_token_limit(
          configured: requested_input_tokens,
          output_tokens: max_output_tokens,
          context_window: context_window
        )
        if @max_input_tokens < requested_input_tokens
          Rails.logger.warn(
            "RAG aggregation input token limit reduced from #{requested_input_tokens} to #{@max_input_tokens} " \
            "to fit the configured context window and output token allowance"
          )
        end
        if @max_input_tokens <= PROMPT_OVERHEAD_TOKENS
          raise ArgumentError, "Analysis input token limit must exceed #{PROMPT_OVERHEAD_TOKENS}"
        end
        @max_retries = Integer(max_retries)
        raise ArgumentError, "Analysis retry count cannot be negative" if @max_retries.negative?

        @retry_delay = Float(retry_delay)
        raise ArgumentError, "Analysis retry delay cannot be negative" if @retry_delay.negative?

        @sleeper = sleeper
      rescue ArgumentError, TypeError => error
        raise error if error.message.start_with?("Analysis", "Model context window")

        raise ArgumentError, "Analysis configuration values must be valid numbers"
      end

      def self.effective_input_token_limit(configured:, output_tokens:, context_window:)
        configured = Integer(configured)
        output_tokens = Integer(output_tokens)
        context_window = Integer(context_window)
        unless configured.positive? && output_tokens.positive? && context_window.positive?
          raise ArgumentError, "Analysis token limits must be positive"
        end

        available = context_window - output_tokens - CONTEXT_WINDOW_SAFETY_TOKENS
        raise ArgumentError, "Model context window is too small for the extraction output limit" unless available.positive?

        [ configured, available ].min
      rescue ArgumentError, TypeError => error
        raise error if error.message.start_with?("Analysis", "Model context window")

        raise ArgumentError, "Analysis token limits must be valid numbers"
      end

      def call(question:, chunks:, progress: nil)
        content_budget = @max_input_tokens - PROMPT_OVERHEAD_TOKENS - estimate_tokens(question.to_s)
        raise ArgumentError, "The question exceeds the configured extraction input token limit" unless content_budget.positive?

        windows = Array(chunks).flat_map { |chunk| split_chunk(chunk, content_budget) }
        batches = build_batches(windows, content_budget)
        Rails.logger.info(
          "RAG aggregation extraction starting: chunks=#{Array(chunks).length} " \
          "windows=#{windows.length} batches=#{batches.length}"
        )
        entities = []
        facts = []
        failures = []

        batches.each_with_index do |batch, index|
          batch_number = index + 1
          notify(progress, batch_number, batches.length, "started")
          attempts = 0

          loop do
            attempts += 1
            begin
              extracted = @extractor.call(question: question, chunks: batch)
              batch_entities = enrich_sources(extracted.fetch(:entities), batch)
              batch_facts = enrich_sources(extracted.fetch(:facts), batch)
            rescue StandardError => error
              if attempts <= @max_retries
                notify(progress, batch_number, batches.length, "retrying", error: error.message, attempt: attempts)
                @sleeper.call(@retry_delay * (2**(attempts - 1))) if @retry_delay.positive?
                next
              end

              failure = BatchFailure.new(
                batch: batch_number,
                chunk_ids: batch.map { |chunk| read_value(chunk, :id) }.uniq,
                attempts: attempts,
                error: error.message
              )
              failures << failure
              Rails.logger.error(
                "RAG aggregation extraction failed for batch #{batch_number}/#{batches.length} " \
                "after #{attempts} attempts: #{error.message}"
              )
              notify(progress, batch_number, batches.length, "failed", error: error.message, attempt: attempts)
              break
            end

            entities.concat(batch_entities)
            facts.concat(batch_facts)
            notify(progress, batch_number, batches.length, "completed")
            break
          end
        end

        Result.new(
          entities: entities,
          facts: facts,
          failed_batches: failures,
          processed_batches: batches.length - failures.length,
          total_batches: batches.length
        )
      end

      private

      def positive_integer(value, label)
        integer = Integer(value)
        raise ArgumentError, "#{label} must be positive" unless integer.positive?

        integer
      end

      def split_chunk(chunk, content_budget)
        content = read_value(chunk, :content).to_s
        overhead = chunk_overhead(chunk)
        if estimate_tokens(CGI.escapeHTML(content)) + overhead <= content_budget
          return [ chunk ]
        end

        available_tokens = content_budget - overhead
        raise ArgumentError, "The configured extraction input limit is too small for chunk metadata" unless available_tokens.positive?

        segments = []
        current_words = []
        content.split(/\s+/).each do |word|
          escaped_word = CGI.escapeHTML(word)
          if estimate_tokens(escaped_word) + overhead > content_budget
            segments << current_words.join(" ") if current_words.any?
            current_words = []
            max_characters = [ available_tokens * 3 / 6, 1 ].max
            word.chars.each_slice(max_characters) do |slice|
              segment = slice.join
              if estimate_tokens(CGI.escapeHTML(segment)) + overhead > content_budget
                raise ArgumentError, "The configured extraction input limit cannot fit a chunk segment"
              end
              segments << segment
            end
          elsif current_words.any? &&
              estimate_tokens(CGI.escapeHTML((current_words + [ word ]).join(" "))) + overhead > content_budget
            segments << current_words.join(" ")
            current_words = [ word ]
          else
            current_words << word
          end
        end
        segments << current_words.join(" ") if current_words.any?
        segments.map { |segment| copy_with_content(chunk, segment) }
      end

      def build_batches(windows, content_budget)
        batches = []
        current = []
        current_tokens = 0

        windows.each do |chunk|
          tokens = estimate_tokens(CGI.escapeHTML(read_value(chunk, :content).to_s)) + chunk_overhead(chunk)
          if current.any? && (current.length >= @batch_size || current_tokens + tokens > content_budget)
            batches << current
            current = []
            current_tokens = 0
          end
          current << chunk
          current_tokens += tokens
        end
        batches << current if current.any?
        batches
      end

      def estimate_tokens(text)
        [ (text.scan(/\S+/).length * 1.5).ceil, (text.length / 3.0).ceil ].max
      end

      def chunk_overhead(chunk)
        estimate_tokens(read_value(chunk, :id).to_s) + 30
      end

      def copy_with_content(chunk, content)
        if chunk.is_a?(Hash)
          chunk.merge(content: content, "content" => content)
        elsif chunk.respond_to?(:to_h)
          chunk.to_h.merge(content: content)
        else
          { id: read_value(chunk, :id), content: content }
        end
      end

      def enrich_sources(records, batch)
        chunk_index = batch.index_by { |chunk| read_value(chunk, :id).to_s }
        Array(records).map do |record|
          source_id = read_value(record, :source_chunk_id).to_s
          source_chunk = chunk_index.fetch(source_id)
          record.to_h.symbolize_keys.merge(
            source_chunk_id: read_value(source_chunk, :id),
            document_id: read_value(source_chunk, :document_id),
            filename: read_value(source_chunk, :filename),
            page_start: read_value(source_chunk, :page_start),
            page_end: read_value(source_chunk, :page_end)
          )
        end
      end

      def notify(callback, batch, total, status, extra = {})
        event = { batch: batch, total_batches: total, status: status }.merge(extra)
        Rails.logger.info("RAG aggregation batch #{batch}/#{total}: #{status}")
        callback.call(event) if callback
      end

      def read_value(record, key)
        return record[key] if record.is_a?(Hash) && record.key?(key)
        return record[key.to_s] if record.is_a?(Hash) && record.key?(key.to_s)
        return record.public_send(key) if record.respond_to?(key)

        nil
      end
    end
  end
end
