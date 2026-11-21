module Rag
  module Evaluation
    class Report
      def render(runs)
        Array(runs).map { |run| render_run(run) }.join("\n\n")
      end

      private

      def render_run(run)
        lines = [
          "RAG Evaluation Report",
          "=" * 52,
          "Dataset: #{run.dataset.name} | Questions: #{run.results.length}",
          "Run ID:  #{run.id}",
          "Started: #{run.started_at.iso8601}",
          *configuration_lines(run.configuration),
          "",
          format("%3s  %-13s %-7s %-7s %s", "#", "Type", "Result", "Score", "Latency"),
          "-" * 52
        ]
        run.results.each_with_index do |result, index|
          lines << format(
            "%3d  %-13s %-7s %-7.2f %6.2fs",
            index + 1,
            result[:type].capitalize,
            result[:status],
            result[:score],
            result[:latency_seconds]
          )
        end

        lines.concat([
          "",
          "-" * 52,
          format("Quality score: %.0f%%", run.metrics.fetch(:quality_score, run.metrics[:average_score]) * 100),
          format("Pass rate:     %.0f%% (%d/%d passed)", run.metrics.fetch(:pass_rate, run.metrics[:accuracy]) * 100, run.metrics[:pass_count], run.results.length)
        ])
        run.metrics[:by_type].each do |type, metrics|
          quality = metrics[:quality_score] || metrics[:average_score] || metrics[:accuracy]
          pass_rate = metrics[:pass_rate] || metrics[:accuracy]
          lines << format("%-14s quality %.0f%% | pass %.0f%%", "#{type.capitalize}:", quality * 100, pass_rate * 100)
        end
        lines.concat([
          "",
          format("Duration:      %.2fs", run.duration_seconds),
          format("Classification: %.2fs", run.results.sum { |result| result.dig(:timings, :classification_seconds).to_f }),
          format("Retrieval:     %.2fs", run.results.sum { |result| result.dig(:timings, :retrieval_seconds).to_f }),
          format("Generation:    %.2fs", run.results.sum { |result| result.dig(:timings, :generation_seconds).to_f }),
          "Embedding:     n/a (not exposed by the retrieval service)",
          "Tokens:        #{run.token_usage[:total_tokens] || 'n/a'}",
          "Cost:          #{run.estimated_cost.nil? ? 'n/a (set RAG_EVAL_*_COST_PER_MILLION_TOKENS)' : format('$%.6f', run.estimated_cost)}"
        ])
        lines.concat(failure_lines(run.results))
        lines << "=" * 52
        lines.join("\n")
      end

      def configuration_lines(configuration)
        llm = configuration[:llm] || {}
        embedding = configuration[:embedding] || {}
        retrieval = configuration[:retrieval] || {}
        [
          "Document:  #{configuration[:document_id] || 'all user documents'}",
          "LLM:       #{llm[:provider]} / #{llm[:model]} (temperature=#{llm[:temperature]}, max_tokens=#{llm[:max_tokens] || 'default'})",
          "Classifier: #{configuration.dig(:classifier, :provider)} / #{configuration.dig(:classifier, :model)} (strategy=#{configuration.dig(:classifier, :strategy) || 'llm'})",
          "Aggregation: #{configuration.dig(:aggregation, :provider)} / #{configuration.dig(:aggregation, :model)} (input_tokens=#{configuration.dig(:aggregation, :max_input_tokens) || 'default'} effective, configured=#{configuration.dig(:aggregation, :configured_max_input_tokens) || 'default'}, output_tokens=#{configuration.dig(:aggregation, :max_tokens) || 'default'}, context_window=#{configuration.dig(:aggregation, :context_window) || 'default'}, batch_size=#{configuration.dig(:aggregation, :batch_size) || 'default'})",
          "Embedding: #{embedding[:provider]} / #{embedding[:model]} (dimensions=#{embedding[:dimensions]})",
          "Retrieval: #{retrieval[:strategy]} Top-K=#{retrieval[:top_k]}, comparative Top-K=#{retrieval[:comparative_top_k]}, threshold=#{retrieval[:threshold].nil? ? 'none' : retrieval[:threshold]}"
        ]
      end

      def failure_lines(results)
        failed = results.reject { |result| result[:status] == "PASS" }
        return [] if failed.empty?

        [ "", "Failed / partial questions:" ] + failed.flat_map do |result|
          [
            "  #{result[:id]} [#{result[:status]}]: #{result[:question]}",
            "    Quality: #{format_score(result[:score])} | answer: #{format_score(result.dig(:answer, :correctness))} | language-cue heuristic: #{format_score(result.dig(:answer, :language_match))} | retrieval coverage: #{format_score(result.dig(:retrieval, :coverage))} | citation validity: #{format_score(result.dig(:retrieval, :citation_accuracy))} | citation relevance: #{format_score(result.dig(:retrieval, :citation_relevance))} | claim support: #{format_score(result.dig(:retrieval, :claim_support))} | cited-term support: #{format_score(result.dig(:retrieval, :faithfulness))}",
            "    Expected: #{result[:expected_answer] || 'insufficient evidence'}",
            "    Actual:   #{visible_answer(result[:actual_answer] || result[:error] || 'No answer')}",
            *error_lines(result),
            *diagnostic_lines(result),
            "    Citations: #{citation_summary(result)}"
          ]
        end
      end

      def diagnostic_lines(result)
        concepts = result.dig(:answer, :concepts) || {}
        relations = result.dig(:answer, :relations) || {}
        aggregation = result[:aggregation] || {}
        lines = []
        lines << "    Missing concepts: #{Array(concepts[:missing]).join(', ')}" if Array(concepts[:missing]).any?
        lines << "    Incorrect concepts: #{Array(concepts[:incorrect]).map { |item| "#{item[:concept]}=#{item[:term]}" }.join(', ')}" if Array(concepts[:incorrect]).any?
        lines << "    Missing relations: #{Array(relations[:missing]).join(', ')}" if Array(relations[:missing]).any?
        lines << "    Claims without cited support: #{Array(result.dig(:retrieval, :unsupported_claims)).join(', ')}" if Array(result.dig(:retrieval, :unsupported_claims)).any?
        if aggregation.key?(:count_accuracy)
          lines << "    Aggregation count: actual=#{aggregation[:actual_count].nil? ? 'n/a' : aggregation[:actual_count]}, expected=#{aggregation[:expected_count] || 'n/a'} (accuracy #{format_score(aggregation[:count_accuracy])})"
          lines << "    Aggregation entity accuracy: #{format_score(aggregation[:entity_accuracy])}"
          lines << "    Extracted entities: #{Array(aggregation[:actual_entities]).join(', ')}" if Array(aggregation[:actual_entities]).any?
        end
        lines << "    Missing aggregation entities: #{Array(aggregation[:missing_entities]).join(', ')}" if Array(aggregation[:missing_entities]).any?
        lines << "    Unexpected aggregation entities: #{Array(aggregation[:unexpected_entities]).join(', ')}" if Array(aggregation[:unexpected_entities]).any?
        if aggregation[:incomplete_batch_count].to_i.positive?
          lines << "    Aggregation extraction incomplete: #{aggregation[:incomplete_batch_count]} batch(es) failed"
          Array(aggregation[:failed_batches]).each do |failure|
            lines << "      Batch #{failure[:batch]} failed after #{failure[:attempts]} attempts (chunks: #{Array(failure[:chunk_ids]).join(', ')}): #{failure[:error]}"
          end
        end
        lines
      end

      def error_lines(result)
        return [] if result[:error].blank?

        [ "    Pipeline error: #{result[:error]}" ]
      end

      def visible_answer(answer)
        answer.to_s
          .gsub(/<think\b[^>]*>.*?<\/think\s*>/im, "")
          .sub(/<think\b[^>]*>.*\z/im, "")
          .split(/\n\nSources:/, 2).first
          .strip
      end

      def citation_summary(result)
        citations = Array(result[:citations])
        return "none" if citations.empty?

        citations.map do |citation|
          label = citation[:label] || citation["label"]
          filename = citation[:filename] || citation["filename"] || "unknown source"
          pages = [ citation[:page_start] || citation["page_start"], citation[:page_end] || citation["page_end"] ].compact.uniq
          page = pages.any? ? " p. #{pages.join('-')}" : ""
          content = citation[:content] || citation["content"]
          excerpt = content.present? ? ": #{content.to_s.squish.truncate(160)}" : ""
          "[#{label}] #{filename}#{page}#{excerpt}"
        end.join(" | ")
      end

      def format_score(value)
        value.nil? ? "n/a" : format("%.2f", value)
      end
    end
  end
end
