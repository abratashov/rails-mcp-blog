module Rag
  class PromptBuilder
    def call(question:, context:, conversation: [], language: nil)
      context_items = Array(context)
      base_language = language || detect_language(question)

      <<~PROMPT
        You are a document-grounded assistant.
        Answer questions using only the retrieved document context supplied below.
        Do not invent facts or cite sources that are not present in the context.
        If the available context is insufficient, say clearly that the evidence is insufficient and explain what is missing.
        Answer in #{base_language} unless the user explicitly requests another language.
        Keep citations distinguishable from normal prose by using bracketed markers like [1], [2].

        #{conversation_prompt(conversation)}

        Retrieved document context:
        #{format_context(context_items)}

        User question:
        #{question.to_s.strip}
      PROMPT
    end

    private

    def conversation_prompt(conversation)
      history = Array(conversation)
      return "" if history.empty?

      lines = ["Conversation history:"]
      history.each do |message|
        role = message.is_a?(Hash) ? message[:role] || message["role"] : message.to_s
        content = message.is_a?(Hash) ? message[:content] || message["content"] : message.to_s
        lines << "#{role.to_s.capitalize}: #{content}"
      end
      lines.join("\n")
    end

    def format_context(context_items)
      return "No relevant document context was retrieved." if context_items.empty?

      context_items.map.with_index(1) do |item, index|
        page_text = [item.page_start, item.page_end].compact.uniq.join("-")
        page_suffix = page_text.present? ? " (page #{page_text})" : ""
        "[#{index}] #{item.filename}#{page_suffix}\n#{item.content}"
      end.join("\n\n")
    end

    def detect_language(question)
      text = question.to_s
      return "english" if text.strip.empty?

      if text.match?(/[А-Яа-яЁёІіЇїЄєҐґ]/)
        return text.match?(/[іІїЇєЄґҐ]/) ? "ukrainian" : "russian"
      end

      "english"
    end
  end
end
