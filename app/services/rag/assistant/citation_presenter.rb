module Rag
  class Assistant
    class CitationPresenter
      INSUFFICIENT_EVIDENCE_PATTERN = /
        insufficient\ evidence
        | couldn't\ find\ enough
        | not\ enough\ relevant
        | no\ relevant\ (?:evidence|information)
        | no\ reference
        | not\ (?:mentioned|covered|referenced)
        | doesn't\ mention
        | does\ not\ mention
        | do\ not\ mention
        | don't\ mention
        | no\ information
        | нет\ информации
        | недостаточно\ информации
        | не\ знайш
        | не\ містить
        | не\ згад
        | не.{0,30}(?:інформац|даних|згад|містить)
        | немає\ (?:достатньої\ )?(?:інформації|даних)
        | не\ вказано
        | не\ зазначено
        | не\ описано
        | не\ упомина
        | не\ указано
        | не\ найден
      /ix

      def build_citations(context)
        context.map.with_index(1) do |item, index|
          {
            label: index,
            source_id: item.source_id,
            source_chunk_id: item.source_chunk_id,
            document_id: item.document_id,
            filename: item.filename,
            page_start: item.page_start,
            page_end: item.page_end,
            position: item.position,
            content: item.content,
            score: item.score,
            distance: item.distance
          }
        end
      end

      def citations_used_by(answer, citations)
        return [] if answer.to_s.match?(INSUFFICIENT_EVIDENCE_PATTERN)

        referenced = citations.select do |citation|
          answer.to_s.match?(/\[#{Regexp.escape(citation[:label].to_s)}\](?!\d)/)
        end
        referenced.presence || citations
      end

      def decorate_with_citations(answer, citations)
        return answer if citations.empty?

        references = citations.map do |citation|
          "[#{citation[:label]}] #{citation[:filename]}#{page_reference(citation)}"
        end.join(" | ")
        "#{answer.strip}\n\nSources: #{references}"
      end

      private

      def page_reference(citation)
        pages = [ citation[:page_start], citation[:page_end] ].compact.uniq
        return "" if pages.empty?

        " (p. #{pages.join("-")})"
      end
    end
  end
end
