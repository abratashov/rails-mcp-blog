require "securerandom"

module Rag
  ContextItem = Struct.new(:source_id, :document_id, :filename, :page_start, :page_end, :position, :content, :score, :distance, :metadata, :context, :token_count, keyword_init: true)

  class ContextAssembler
    DEFAULT_MAX_TOKENS = 4_000

    def initialize(max_tokens: DEFAULT_MAX_TOKENS)
      @max_tokens = max_tokens.to_i
      raise ArgumentError, "Context budget must be positive" if @max_tokens <= 0
    end

    def call(results, max_tokens: @max_tokens)
      items = Array(results).compact
      return [] if items.empty?

      deduplicated = deduplicate(items)
      selected = []
      total_tokens = 0
      budget = max_tokens.to_i

      deduplicated.sort_by { |item| [-(numeric_value(item, :score) || 0.0), integer_value(item, :position)] }.each do |result|
        source_text = format_context_entry(result, selected.length + 1)
        token_count = estimate_tokens(source_text)
        next if token_count.zero?

        if total_tokens + token_count <= budget
          selected << build_item(result, source_text, token_count)
          total_tokens += token_count
        elsif total_tokens < budget
          remaining = budget - total_tokens
          if remaining.positive?
            truncated = truncate_to_tokens(source_text, remaining)
            selected << build_item(result, truncated, remaining)
            total_tokens += remaining
          end
        end
        break if total_tokens >= budget
      end

      selected
    end

    private

    def deduplicate(results)
      seen = {}
      results.each_with_object([]) do |result, filtered|
        key = [read_value(result, :document_id), read_value(result, :position), read_value(result, :content).to_s.strip]
        next if seen[key]

        seen[key] = true
        filtered << result
      end
    end

    def format_context_entry(result, index)
      page_reference = page_reference_for(result)
      lines = []
      lines << "[Source #{index}] #{read_value(result, :filename)}#{page_reference}"
      lines << read_value(result, :content).to_s.strip
      lines.join("\n")
    end

    def page_reference_for(result)
      pages = [read_value(result, :page_start), read_value(result, :page_end)].compact.uniq
      return "" if pages.empty?

      page_text = pages.join("-")
      " (page #{page_text})"
    end

    def build_item(result, source_text, token_count)
      match = source_text[/\[Source (\d+)\]/, 1]
      ContextItem.new(
        source_id: match || SecureRandom.uuid,
        document_id: read_value(result, :document_id),
        filename: read_value(result, :filename),
        page_start: read_value(result, :page_start),
        page_end: read_value(result, :page_end),
        position: read_value(result, :position),
        content: read_value(result, :content).to_s.strip,
        score: read_value(result, :score),
        distance: read_value(result, :distance),
        metadata: read_value(result, :metadata) || {},
        context: source_text,
        token_count: token_count
      )
    end

    def numeric_value(result, key)
      value = read_value(result, key)
      value.to_f if value.respond_to?(:to_f)
    end

    def integer_value(result, key)
      value = read_value(result, key)
      value.to_i if value.respond_to?(:to_i)
    end

    def read_value(result, key)
      return result[key.to_s] if result.is_a?(Hash) && result.key?(key.to_s)
      return result[key] if result.is_a?(Hash) && result.key?(key)
      return result.public_send(key) if result.respond_to?(key)

      nil
    end

    def estimate_tokens(text)
      return 0 if text.to_s.empty?

      (text.scan(/\S+/).size * 1.3).ceil
    end

    def truncate_to_tokens(text, remaining_tokens)
      return text if remaining_tokens <= 0

      tokens = text.to_s.split(/\s+/)
      length = [remaining_tokens, tokens.length].min
      tokens.first(length).join(" ")
    end
  end
end
