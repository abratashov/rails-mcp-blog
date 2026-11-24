module Rag
  module Strategies
    module Comparative
      class QueryBuilder
        Query = Struct.new(:subject, :aspect, :text, keyword_init: true)

        SUBJECT_SEPARATOR = /
          \s+
          (?:
            and|with|to|against|vs\.?|versus|
            і|й|та|з|із|зі|
            и|с|со
          )
          \s+
        /ix

        COMPARISON_VERB = /
          (?:
            compare|compares|comparing|
            порівняй(?:те)?|порівняти|
            сравни(?:те)?|сравнить
          )
        /ix

        BETWEEN_PHRASE = /
          (?:
            (?:what\s+are\s+the\s+)?(?:differences|similarities|relationship)\s+between
            |(?:які\s+)?(?:відмінності|різниця|різниці|схожість|подібність|зв'язок|взаємозв'язок|пов'язані)\s+між
            |(?:какие\s+)?(?:различия|разница|сходство|связь|связаны)\s+между
            |в\s+чём\s+(?:разница|различие)\s+между
            |в\s+чем\s+(?:разница|различие)\s+между
          )
        /ix

        SCOPE_SUFFIX = /
          \s+
          (?:
            across|in\s+terms\s+of|in|on|for|regarding|based\s+on|
            за|щодо|стосовно|з\s+точки\s+зору|у\s+контексті|
            по|в\s+плане|с\s+точки\s+зрения|относительно|в\s+контексте
          )
          \s+(.+)\z
        /ix

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
            /\A(?:#{COMPARISON_VERB}\s+)?(?<left>.+?)\s+(?:vs\.?|versus)\s+(?<right>.+)\z/i
          )
          match ||= question.match(
            /\A#{COMPARISON_VERB}\s+(?<left>.+?)#{SUBJECT_SEPARATOR}(?<right>.+)\z/i
          )
          match ||= question.match(
            /\A#{BETWEEN_PHRASE}\s+(?<left>.+?)#{SUBJECT_SEPARATOR}(?<right>.+)\z/i
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
end
