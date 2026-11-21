require "yaml"

module Rag
  module Evaluation
    class DatasetLoader
      Dataset = Struct.new(:name, :questions, keyword_init: true)

      def initialize(directory: Rails.root.join("spec/fixtures/rag/evaluation"))
        @directory = Pathname.new(directory)
      end

      def all
        dataset_paths.map { |path| load_path(path) }.index_by(&:name)
      end

      def load(name)
        path = @directory.join("#{name}.yml")
        raise ArgumentError, "Evaluation dataset not found: #{name}" unless path.file?

        load_path(path)
      end

      private

      def dataset_paths
        paths = @directory.glob("*.yml").sort
        raise ArgumentError, "No evaluation datasets found in #{@directory}" if paths.empty?

        paths
      end

      def load_path(path)
        data = YAML.safe_load_file(path, permitted_classes: [], aliases: false)
        unless data.is_a?(Hash) && data["questions"].is_a?(Array) && data["questions"].any?
          raise ArgumentError, "Evaluation dataset #{path.basename} must define questions"
        end

        questions = data.fetch("questions").each_with_index.map do |question, index|
          validate_question(question, path, index + 1)
        end
        Dataset.new(name: data["name"].presence || path.basename(".yml").to_s, questions: questions)
      rescue Psych::Exception => error
        raise ArgumentError, "Invalid evaluation dataset #{path}: #{error.message}"
      end

      def validate_question(question, path, index)
        unless question.is_a?(Hash) &&
            question["id"].present? &&
            question["question"].present? &&
            %w[specific comparative aggregation].include?(question["type"])
          raise ArgumentError, "Evaluation question #{index} in #{path.basename} requires id, question, and a valid type"
        end

        unless question["expected_answer"].present? || question["insufficient_evidence"] == true
          raise ArgumentError, "Evaluation question #{question['id']} requires an expected answer or insufficient_evidence"
        end

        question
      end
    end
  end
end
