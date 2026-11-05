module Documents
  class Chunker
    DEFAULT_TARGET_SIZE = 1_200
    DEFAULT_OVERLAP = 0

    def initialize(target_size: ENV.fetch("DOCUMENT_CHUNK_SIZE", DEFAULT_TARGET_SIZE).to_i,
                   overlap: ENV.fetch("DOCUMENT_CHUNK_OVERLAP", DEFAULT_OVERLAP).to_i)
      raise ArgumentError, "Chunk target size must be positive" unless target_size.positive?
      raise ArgumentError, "Chunk overlap must be non-negative and leave room for chunk content" unless overlap >= 0 && target_size > overlap + (overlap.positive? ? 2 : 0)

      @target_size = target_size
      @overlap = overlap
    end

    def call(segments)
      atoms = segments.flat_map { |segment| segment_atoms(segment) }
      build_chunks(atoms)
    end

    private

    def segment_atoms(segment)
      text = segment.fetch(:content).to_s.strip
      return [] if text.blank?

      metadata = segment.fetch(:metadata, {})
      metadata = metadata.merge("heading" => text) if metadata["kind"] == "heading"
      source = { page_number: segment[:page_number], metadata: metadata }.compact
      atom_limit = @target_size - @overlap - (@overlap.positive? ? 2 : 0)
      return [ { content: text, sources: [ source ] } ] if text.length <= atom_limit

      split_sentences(text).flat_map do |sentence|
        split_long_text(sentence).map { |part| { content: part, sources: [ source ] } }
      end
    end

    def split_sentences(text)
      text.split(/(?<=[.!?。！？])\s+/).reject(&:blank?)
    end

    def split_long_text(text)
      atom_limit = @target_size - @overlap - (@overlap.positive? ? 2 : 0)
      return [ text ] if text.length <= atom_limit

      parts = []
      remaining = text
      until remaining.empty?
        candidate = remaining[0, atom_limit]
        boundary = candidate.rindex(/\s/)
        boundary = atom_limit if boundary.nil? || boundary.zero?
        parts << remaining[0, boundary].strip
        remaining = remaining[boundary..].to_s.strip
      end
      parts
    end

    def build_chunks(atoms)
      chunks = []
      current = []
      index = 0

      while index < atoms.length
        atom = atoms[index]
        if current.empty? || joined_length(current + [ atom ]) <= @target_size
          current << atom
          index += 1
        else
          chunks << build_chunk(current)
          current = overlap_atoms(current)
          current = [] if joined_length(current + [ atom ]) > @target_size
        end
      end

      chunks << build_chunk(current) if current.any?
      chunks.each_with_index.map { |chunk, position| chunk.merge(position: position + 1) }
    end

    def overlap_atoms(atoms)
      selected = []
      atoms.reverse_each do |atom|
        candidate = [ atom ] + selected
        break if joined_length(candidate) > @overlap

        selected = candidate
      end
      return selected if selected.any?

      last = atoms.last
      return [] unless last && @overlap.positive?

      content = last[:content]
      suffix = content[-@overlap, @overlap].to_s
      boundary = suffix.index(/\s/)
      suffix = boundary ? suffix[(boundary + 1)..].to_s : ""
      return [] if suffix.blank?

      [ last.merge(content: suffix) ]
    end

    def joined_length(atoms)
      atoms.sum { |atom| atom[:content].length } + [ atoms.length - 1, 0 ].max * 2
    end

    def build_chunk(atoms)
      sources = atoms.flat_map { |atom| atom[:sources] }.uniq
      pages = sources.filter_map { |source| source[:page_number] }
      source_metadata = sources.map { |source| source[:metadata] }.compact

      {
        content: atoms.map { |atom| atom[:content] }.join("\n\n"),
        page_start: pages.min,
        page_end: pages.max,
        metadata: {
          "source_segments" => source_metadata,
          "headings" => source_metadata.filter_map { |metadata| metadata["heading"] }.uniq
        }
      }
    end
  end
end
