module Rag
  module Comparative
    class QueryBuilder
      Query = Struct.new(:subject, :aspect, :text, keyword_init: true)

      SUBJECT_SEPARATOR = /\s+(?:and|with|to|against|vs\.?|versus)\s+/i
      SCOPE_SUFFIX = /\s+(?:across|in terms of|in|on|for|regarding|based on)\s+(.+)\z/i

      def call(question)
        text = question.to_s.strip
        subjects, aspect = extract_subjects_and_aspect(text)
        return [ Query.new(subject: nil, aspect: nil, text: text) ] if subjects.blank?

        subjects.map do |subject|
          query_text = [ subject, aspect ].compact_blank.join(" ")
          Query.new(subject: subject, aspect: aspect, text: query_text)
        end
      end

      private

      def extract_subjects_and_aspect(question)
        match = question.match(
          /\A(?:compare\s+)?(?<left>.+?)\s+(?:vs\.?|versus)\s+(?<right>.+)\z/i
        )
        match ||= question.match(
          /\Acompare\s+(?<left>.+?)#{SUBJECT_SEPARATOR}(?<right>.+)\z/i
        )
        match ||= question.match(
          /\A(?:what\s+are\s+the\s+)?(?:differences|similarities|relationship)\s+between\s+(?<left>.+?)\s+and\s+(?<right>.+)\z/i
        )
        return [ [], nil ] unless match

        left = clean_subject(match[:left])
        right_text, aspect = split_aspect(match[:right])
        right = clean_subject(right_text)
        return [ [], nil ] if left.blank? || right.blank?

        [ [ left, right ].uniq, aspect ]
      end

      def split_aspect(text)
        match = text.match(SCOPE_SUFFIX)
        return [ text, nil ] unless match

        possible_aspect = match[1].sub(/[?.!]+\z/, "").strip
        if possible_aspect.match?(/\A(?:all\s+)?(?:uploaded\s+)?documents?\z/i)
          return [ text[0...match.begin(0)], nil ]
        end

        [ text[0...match.begin(0)], possible_aspect.presence ]
      end

      def clean_subject(text)
        text.to_s.sub(/[?.!,;:]+\z/, "").strip
      end
    end
  end
end
