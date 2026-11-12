ActiveAdmin.register_page "Semantic Search" do
  menu parent: "Documents", priority: 4

  page_action :search, method: :post do
    search_params = params.fetch(:search, params)
    @query = search_params[:query]
    @selected_identity = search_params[:embedding_identity]

    begin
      raise Retrieval::SearchConfiguration::ConfigurationError, "Choose an embedding model" if @selected_identity.blank?

      identity = JSON.parse(@selected_identity)
      unless identity.is_a?(Hash)
        raise Retrieval::SearchConfiguration::ConfigurationError, "Embedding identity must be an object"
      end

      identity = identity.symbolize_keys
      identities = DocumentChunkEmbedding
        .joins(document_chunk: :document)
        .where(documents: { user_id: current_user.id }, status: "completed")
        .distinct
        .pluck(:provider, :model, :dimensions, :configuration_version)
        .map do |provider, model, dimensions, configuration_version|
          { provider: provider, model: model, dimensions: dimensions, configuration_version: configuration_version }
        end
      raise Retrieval::SearchConfiguration::ConfigurationError, "Choose an available embedding model" unless identities.include?(identity)

      metadata_filter = search_params[:metadata_filter].presence
      metadata_filter = JSON.parse(metadata_filter) if metadata_filter
      unless metadata_filter.nil? || metadata_filter.is_a?(Hash)
        raise ArgumentError, "Chunk metadata filter must be a JSON object"
      end

      configuration = Retrieval::SearchConfiguration.new(
        embedding_identity: identity,
        top_k: search_params[:top_k],
        threshold: search_params[:threshold],
        metric: search_params[:metric]
      )

      @search_results = Retrieval::SemanticSearch.new(configuration: configuration).call(
        @query,
        user: current_user,
        document_id: search_params[:document_id],
        metadata: metadata_filter
      )

      @search_identity = identity
    rescue JSON::ParserError, ArgumentError, Embeddings::Provider::Error,
        Embeddings::Configuration::ConfigurationError, Retrieval::SearchConfiguration::ConfigurationError => error
      @search_error = error.message
    end
    render :index, layout: false
  end

  content title: "Semantic Search" do
    search_params = params.fetch(:search, params)
    identity_rows = DocumentChunkEmbedding
      .joins(document_chunk: :document)
      .where(documents: { user_id: current_user.id }, status: "completed")
      .distinct
      .order(:model)
      .pluck(:provider, :model, :dimensions, :configuration_version)

    identities = identity_rows.map do |provider, model, dimensions, configuration_version|
      {
        provider: provider,
        model: model,
        dimensions: dimensions,
        configuration_version: configuration_version
      }
    end

    identity_options = identities.map do |identity|
      label = "#{identity[:provider]} / #{identity[:model]} (#{identity[:dimensions]} dimensions, configuration #{identity[:configuration_version]})"
      [ label, identity.to_json ]
    end

    selected_identity = assigns[:selected_identity].presence || identity_options.first&.last

    panel "Search documents" do
      form_for :search, url: admin_semantic_search_search_path, method: :post,
                        html: { class: "semantic-search-form" } do |form|
        div class: "inputs" do
          div class: "input" do
            concat form.label :query, "What would you like to find?"
            concat form.search_field :query, value: assigns[:query], required: true,
              placeholder: "Ask a question about your documents"
          end
        end

        div class: "actions" do
          concat form.submit "Search"
        end

        details class: "semantic-search-advanced" do
          summary "Advanced options"
          div class: "inputs" do
            div class: "input" do
              concat form.label :embedding_identity, "Embedding model"
              concat form.select :embedding_identity, options_for_select(identity_options, selected_identity), include_blank: "Select a model"
            end

            div class: "input" do
              concat form.label :document_id, "Limit to document"
              documents = current_user.documents.order(:filename).pluck(:filename, :id)
              concat form.select :document_id, options_for_select(documents, search_params[:document_id]), include_blank: "All my documents"
            end

            div class: "input" do
              concat form.label :top_k, "Number of results"
              concat form.number_field :top_k, value: search_params[:top_k] || Retrieval::SearchConfiguration::DEFAULT_TOP_K, min: 1, max: Retrieval::SearchConfiguration::MAX_TOP_K
            end

            div class: "input" do
              concat form.label :metric, "Distance metric"
              concat form.select :metric, options_for_select(
                Retrieval::SearchConfiguration::METRICS.map { |metric| [ metric.humanize, metric ] },
                search_params[:metric] || "cosine"
              )
            end

            div class: "input" do
              concat form.label :threshold, "Similarity threshold (optional)"
              concat form.number_field :threshold, value: search_params[:threshold], step: :any
            end

            div class: "input" do
              concat form.label :metadata_filter, "Chunk metadata filter (JSON, optional)"
              concat form.text_field :metadata_filter, value: search_params[:metadata_filter]
            end
          end
        end
      end
    end

    if assigns[:search_error]
      para assigns[:search_error], class: "error"
    end

    if assigns[:search_results]
      panel "Results for: #{assigns[:query]}" do
        para "Embedding model: #{assigns[:search_identity].values_at(:provider, :model, :dimensions, :configuration_version).join(' / ')}"
        if assigns[:search_results].empty?
          para "No matching chunks found."
        else
          table_for assigns[:search_results] do
            column("Source") do |result|
              link_to "#{result.filename} · document #{result.document_id}",
                admin_document_path(result.document_id)
            end

            column("Pages") do |result|
              [ result.page_start, result.page_end ].compact.uniq.join("–")
            end

            column("Chunk position", &:position)
            column("Score (#{assigns[:search_identity][:model]})", &:score)
            column("Distance (#{search_params[:metric] || "cosine"})", &:distance)
            column(:content)
            column("Metadata", &:metadata)
          end
        end
      end
    end
  end
end
