module Rag
  module Evaluation
    class AnswerEvaluator
      STOP_WORDS = %w[
        a an and are as at be by for from in is it of on or that the their this to with
        та й є за з із у в на для про як і це
        а без в во для до за из к на о от по при с со у и это
      ].freeze

      def call(question, result)
        if question["insufficient_evidence"] == true
          no_evidence = result.answer.to_s.match?(
            /insufficient|couldn't find|not enough|no (?:relevant )?(?:evidence|information)|no reference|not (?:mentioned|covered|referenced)|doesn't mention|does not mention|do not mention|don't mention|no information|нет информации|недостаточно информации|недостат|не знайш|не містить|не згад|не.{0,30}(?:інформац|даних|згад|містить)|немає (?:достатньої )?(?:інформації|даних)|не вказано|не зазначено|не описано|не упомина|не указано|не найден/i
          )
          return {
            correctness: no_evidence ? 1.0 : 0.0,
            completeness: no_evidence ? 1.0 : 0.0,
            concept_coverage: no_evidence ? 1.0 : 0.0,
            language_match: language_match(question["language"], visible_answer(result.answer)),
            concepts: empty_concept_metrics,
            relations: empty_relation_metrics,
            expected_terms: [],
            matched_terms: [],
            insufficient_evidence_correct: no_evidence
          }
        end

        terms = expected_term_groups(question)
        answer_text = visible_answer(result.answer)
        normalized_answer = normalize(answer_text)
        matched = terms.select do |group|
          group.any? { |term| normalized_answer.include?(normalize(term)) }
        end
        term_recall = terms.empty? ? 1.0 : matched.length.to_f / terms.length
        aggregation_question = question["type"] == "aggregation"
        concept_metrics = aggregation_question ? empty_concept_metrics : evaluate_concepts(question, answer_text)
        relation_metrics = aggregation_question ? empty_relation_metrics : evaluate_relations(question, answer_text)
        scores = [ term_recall ]
        scores << concept_metrics[:recall] if concept_metrics[:total].positive?
        scores << relation_metrics[:recall] if relation_metrics[:total].positive?
        correctness = scores.sum / scores.length
        correctness = [ correctness, relation_metrics[:recall] ].min if relation_metrics[:total].positive?

        {
          correctness: correctness,
          completeness: term_recall == 1.0 ? 1.0 : 0.0,
          concept_coverage: concept_metrics[:total].positive? ? concept_metrics[:recall] : term_recall,
          language_match: language_match(question["language"], answer_text),
          expected_terms: terms.flatten,
          matched_terms: matched.map { |group| group.find { |term| normalized_answer.include?(normalize(term)) } },
          concepts: concept_metrics,
          relations: relation_metrics,
          insufficient_evidence_correct: nil
        }
      end

      private

      def expected_term_groups(question)
        answer_groups = Array(question["answer_term_groups"])
        return answer_groups.map { |group| Array(group).map(&:to_s) } if answer_groups.any?

        groups = Array(question["expected_term_groups"])
        return groups.map { |group| Array(group).map(&:to_s) } if groups.any?

        terms = Array(question["expected_terms"]).presence || significant_terms(question["expected_answer"])
        terms.map { |term| [ term.to_s ] }
      end

      def visible_answer(text)
        text.to_s
          .gsub(/<think\b[^>]*>.*?<\/think\s*>/im, "")
          .sub(/<think\b[^>]*>.*\z/im, "")
          .split(/\n\nSources:/, 2).first
      end

      def significant_terms(text)
        normalize(text).split.reject { |word| word.length < 2 || STOP_WORDS.include?(word) }.uniq
      end

      def normalize(text)
        text.to_s.unicode_normalize(:nfkc).downcase.scan(/[\p{Alnum}\p{Han}\p{Hiragana}\p{Katakana}]+/u).join(" ")
      end

      def language_match(language, text)
        return if language.blank?

        words = normalize(text).split
        hits = LANGUAGE_MARKERS.transform_values do |markers|
          words.count { |word| markers.include?(word) }
        end
        expected = hits.fetch(language.to_s, 0)
        foreign = hits.except(language.to_s).values.sum
        return if expected.zero? && foreign.zero?

        expected.to_f / [ expected + foreign, 1 ].max
      end

      def evaluate_concepts(question, answer)
        concepts = Array(question["gold_concepts"])
        found = concepts.select do |concept|
          aliases_present?(answer, concept["aliases"]) &&
            !Array(concept["incorrect_aliases"]).any? { |alias_text| aliases_present?(answer, [ alias_text ]) }
        end
        wrong = concepts.flat_map do |concept|
          Array(concept["incorrect_aliases"]).filter_map do |alias_text|
            { concept: concept["id"], term: alias_text } if aliases_present?(answer, [ alias_text ])
          end
        end
        {
          total: concepts.length,
          found: found.map { |concept| concept["id"] },
          missing: concepts.reject { |concept| found.include?(concept) }.map { |concept| concept["id"] },
          incorrect: wrong,
          recall: concepts.empty? ? 1.0 : found.length.to_f / concepts.length
        }
      end

      def evaluate_relations(question, answer)
        expected = Array(question["gold_relations"])
        claims = answer_sentences(answer, question)
        found = expected.select do |relation|
          claims.any? { |claim| relation_supported?(relation, claim, question) }
        end
        {
          total: expected.length,
          found: found.map { |relation| "#{relation['subject']} -> #{relation['object']}" },
          missing: expected.reject { |relation| found.include?(relation) }
            .map { |relation| "#{relation['subject']} -> #{relation['object']}" },
          recall: expected.empty? ? 1.0 : found.length.to_f / expected.length
        }
      end

      def relation_supported?(relation, claim, question)
        concepts = Array(question["gold_concepts"]).index_by { |concept| concept["id"] }
        subject = concepts[relation["subject"]]
        object = concepts[relation["object"]]
        return false unless subject && object

        subject_position = earliest_alias_position(claim, subject["aliases"])
        object_position = earliest_alias_position(claim, object["aliases"])
        return false unless subject_position && object_position && subject_position < object_position

        Array(relation["predicate_aliases"]).any? do |predicate|
          predicate_position = earliest_alias_position(claim, [ predicate ])
          predicate_position && predicate_position > subject_position && predicate_position < object_position
        end
      end

      def earliest_alias_position(text, aliases)
        Array(aliases).filter_map do |alias_text|
          normalized_alias = normalize(alias_text)
          next if normalized_alias.blank?

          match = /(?:\A| )#{Regexp.escape(normalized_alias)}(?= |\z)/.match(text)
          match.begin(0) + (match[0].length - match[0].lstrip.length) if match
        end.min
      end

      def aliases_present?(text, aliases)
        !earliest_alias_position(normalize(text), aliases).nil?
      end

      def answer_sentences(text, question)
        concepts = Array(question["gold_concepts"]).index_by { |concept| concept["id"] }
        subject_aliases = Array(question["gold_relations"]).flat_map do |relation|
          Array(concepts.dig(relation["subject"], "aliases"))
        end.uniq.sort_by { |alias_text| -alias_text.length }
        subject_pattern = subject_aliases.map { |alias_text| Regexp.escape(alias_text) }.join("|")
        comma_before_subject = subject_pattern.present? ? ",(?=\\s*(?:#{subject_pattern})(?:\\b|\\s))" : "(?!)"
        splitter = /(?:[.!?;]|\bwhile\b|\bwhereas\b|\bbut\b|\bа\b|тоді як|тогда как|#{comma_before_subject})/i
        text.to_s.split(splitter)
          .map { |sentence| normalize(sentence) }
          .reject(&:blank?)
      end

      def empty_concept_metrics
        { total: 0, found: [], missing: [], incorrect: [], recall: 1.0 }
      end

      def empty_relation_metrics
        { total: 0, found: [], missing: [], recall: 1.0 }
      end

      LANGUAGE_MARKERS = {
        "en" => %w[the is are in of to with while and but this they their called live inhabit],
        "ua" => %w[що це та як у з із на для або тоді лев леви левів живе живуть прайдом прайдами тигр тигри],
        "ru" => %w[что это и как в из на для или тогда лев левы тигр тигры живет живут обычно одиночку]
      }.freeze
    end
  end
end
