module Content
  class SyncRunner
    Result = Struct.new(:documents, :run, keyword_init: true)

    def initialize(mode: default_mode, source: nil, parser: MarkdownParser.new)
      @mode = mode
      @source = source
      @parser = parser
    end

    def call(raise_on_error: true)
      run = ContentSyncRun.create!(
        source_mode: @mode,
        source_location: source_location,
        status: :running,
        started_at: Time.current
      )

      documents = Importer.new(source: source, parser: @parser).call
      run.update!(
        status: :succeeded,
        document_count: documents.size,
        finished_at: Time.current,
        error_message: nil
      )

      Result.new(documents: documents, run: run)
    rescue StandardError => error
      run&.update!(
        status: :failed,
        finished_at: Time.current,
        error_message: truncate_error(error)
      )

      raise if raise_on_error

      Rails.logger.error("Study content sync failed: #{error.class}: #{error.message}")
      Result.new(documents: [], run: run)
    end

    private

    def source
      @source ||= begin
        case @mode
        when "github"
          GithubSource.new
        else
          FilesystemSource.new
        end
      end
    end

    def source_location
      if source.respond_to?(:source_location)
        source.source_location
      elsif source.respond_to?(:root_path)
        source.root_path.to_s
      else
        @mode
      end
    end

    def default_mode
      ENV.fetch("STUDY_CONTENT_MODE", Rails.env.production? ? "github" : "filesystem")
    end

    def truncate_error(error)
      "#{error.class}: #{error.message}".truncate(500)
    end
  end
end
