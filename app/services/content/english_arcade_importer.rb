require "digest"
require "json"
require "pathname"
require "yaml"

module Content
  # Builds the small, stable integration index used by the English Arcade.
  #
  # The two source repositories remain the source of truth.  This adapter only
  # stores identifiers, paths, checksums and relationships; it deliberately
  # does not copy Markdown or the TypeScript seed into the cockpit.
  class EnglishArcadeImporter
    SOURCE_ID_PREFIX = "system-design-estudos"
    ARCADE_SOURCE_ID_PREFIX = "english-arcade"
    CURRICULUM_PATH = "curriculum.yml"
    LEGACY_SEED_PATH = "src/data/seed.ts"
    TARGETS = %w[dsa ruby rails react golang elixir salesforce system_design].freeze
    CORPUS_KINDS = %w[chapter lab capstone review_card decision_contrast curriculum].freeze
    PACK_MIN_ITEMS_PER_TARGET = 12
    PACK_REQUIRED_FIELDS = %w[prompt context answer distractors feedback rephrase].freeze
    LINK_KEYS = %w[foundations notes playbooks bridge_labs simulations].freeze
    PACK_DIRECTORY = "db/seeds/english_arcade"
    EXTERNAL_CONTENT_FILES = %w[
      app/services/content/english_arcade_content.rb
      db/seeds/english_arcade_content.rb
      config/english_arcade_content.yml
      config/english_arcade_content.yaml
      config/english_arcade_content.json
    ].freeze

    Record = Struct.new(
      :source_id,
      :target,
      :kind,
      :title,
      :source_path,
      :source_checksum,
      :metadata,
      :search_text,
      keyword_init: true
    ) do
      def to_h
        {
          "source_id" => source_id,
          "target" => target,
          "kind" => kind,
          "title" => title,
          "source_path" => source_path,
          "source_checksum" => source_checksum,
          "metadata" => metadata,
          "search_text" => search_text
        }
      end

      def [](key)
        to_h.fetch(key.to_s)
      end
    end

    Link = Struct.new(:source_id, :target_source_id, :relation, :target_path, keyword_init: true) do
      def to_h
        {
          "source_id" => source_id,
          "target_source_id" => target_source_id,
          "relation" => relation,
          "target_path" => target_path
        }
      end
    end

    Result = Struct.new(:records, :links, :warnings, :persisted_count, keyword_init: true) do
      def to_h
        {
          "records" => records.map(&:to_h),
          "links" => links.map(&:to_h),
          "warnings" => warnings,
          "persisted_count" => persisted_count,
          "pack_readiness" => pack_readiness
        }
      end

      def pack_readiness
        return @pack_readiness if defined?(@pack_readiness)

        packs = records.select { |record| record.kind == "interview_pack" }
        by_target = packs.group_by(&:target)
        targets = by_target.transform_values do |items|
          field_counts = PACK_REQUIRED_FIELDS.to_h do |field|
            [ field, items.count { |record| record.metadata.is_a?(Hash) && record.metadata[field].present? } ]
          end
          {
            "item_count" => items.size,
            "required_field_counts" => field_counts,
            "missing_fields" => PACK_REQUIRED_FIELDS.select { |field| field_counts[field] < items.size }
          }
        end
        missing_targets = TARGETS - by_target.keys
        @pack_readiness = {
          "minimum_items_per_target" => PACK_MIN_ITEMS_PER_TARGET,
          "required_fields" => PACK_REQUIRED_FIELDS,
          "target_count" => by_target.size,
          "item_count" => packs.size,
          "targets" => targets,
          "missing_targets" => missing_targets,
          "ready" => missing_targets.empty? && targets.values.all? { |summary| summary.fetch("item_count") >= PACK_MIN_ITEMS_PER_TARGET && summary.fetch("missing_fields").empty? },
          "legacy_item_count" => records.count { |record| record.kind == "legacy_arcade_item" }
        }
      end
    end

    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super("English Arcade corpus is invalid: #{errors.join("; ")}")
      end
    end

    attr_reader :corpus_root, :arcade_root

    def initialize(
      corpus_root: default_corpus_root,
      arcade_root: default_arcade_root,
      external_records: nil,
      persist: false,
      relation: nil
    )
      @corpus_root = Pathname(corpus_root).expand_path
      @arcade_root = Pathname(arcade_root).expand_path
      @external_records = external_records
      @persist = persist
      @relation = relation
      @result = nil
    end

    # Consistent with Content::Importer, #call is the record list.  Use #result
    # when callers also need link/warning counts.
    def call
      result.records
    end

    alias records call

    def result
      @result ||= build_result
    end

    # Redacted readiness evidence: counts and field names only, never prompt,
    # answer, distractor or feedback values.
    def pack_readiness
      result.pack_readiness
    end

    def import!
      report = result
      persisted_count = persist_study_document_metadata(report.records, report.links)
      report.persisted_count = persisted_count
      report
    end

    alias sync! import!

    def validate!
      errors = validation_errors(result.records)
      raise ValidationError, errors if errors.any?

      true
    end

    def validation_errors(records = result.records)
      records.each_with_object([]) do |record, errors|
        errors << "#{record.source_id}: missing source_path" if record.source_path.to_s.empty?
        errors << "#{record.source_id}: missing stable source_id" if record.source_id.to_s.empty?
        if record.target.present? && !TARGETS.include?(record.target) && record.target != "legacy"
          errors << "#{record.source_id}: unsupported target #{record.target.inspect}"
        end

        next unless record.kind == "interview_pack"

        required = %w[prompt context answer distractors feedback rephrase]
        required.each do |field|
          value = record.metadata[field] || record.metadata[field.to_sym]
          errors << "#{record.source_id}: missing #{field}" if value.blank?
        end
      end
    end

    def self.source_id_for(path)
      "#{SOURCE_ID_PREFIX}:#{Pathname(path).to_s.sub(%r{\A\./}, "")}"
    end

    def self.arcade_source_id_for(item_id)
      "#{ARCADE_SOURCE_ID_PREFIX}:legacy:item:#{item_id}"
    end

    private

    def build_result
      @records = {}
      @links = []
      @warnings = []

      add_curriculum_record
      add_curriculum_chapters
      add_directory_records("lab", "labs/chapters/chapter-*.md")
      add_directory_records("review_card", "reviews/cards/*.md")
      add_directory_records("decision_contrast", "decision-contrasts/[0-9][0-9]-*.md")
      add_directory_records("capstone", "capstones/[0-9][0-9]-*.md")
      add_legacy_arcade_records
      add_external_records
      attach_links_to_metadata

      Result.new(records: @records.values.sort_by { |record| [ record.kind, record.source_id ] }, links: unique_links, warnings: @warnings, persisted_count: 0)
    end

    def add_curriculum_record
      path = corpus_root.join(CURRICULUM_PATH)
      return unless path.file?

      curriculum = safe_yaml(path)
      add_record(
        kind: "curriculum",
        target: "system_design",
        source_path: CURRICULUM_PATH,
        title: curriculum["title"].presence || "System Design Estudos curriculum",
        source_checksum: Digest::SHA256.file(path).hexdigest,
        metadata: {
          "version" => curriculum["version"],
          "canonical_source" => curriculum["canonical_source"],
          "phase_ids" => Array(curriculum["phases"]).filter_map { |phase| phase["id"] }
        }.compact
      )
    end

    def add_curriculum_chapters
      curriculum = safe_yaml(corpus_root.join(CURRICULUM_PATH))
      chapters = Array(curriculum["chapters"])

      chapters.each do |chapter|
        path = chapter["path"].to_s
        next if path.empty?

        chapter_id = chapter.fetch("id")
        metadata = {
          "curriculum_id" => chapter_id,
          "chapter_number" => chapter["number"],
          "phase_id" => chapter["phase"],
          "primary_area" => chapter["primary_area"],
          "secondary_areas" => Array(chapter["secondary_areas"]),
          "canonical_source" => path
        }.compact

        add_record(kind: "chapter", target: "system_design", source_path: path, title: chapter["title"], metadata: metadata)
        add_link("curriculum.yml", path, "chapter")

        relation_paths(chapter).each do |relation, related_path|
          next if related_path.to_s.empty?

          related_kind = kind_for_path(related_path)
          add_record_from_path(related_kind, related_path)
          add_link(path, related_path, relation)
        end
      end
    end

    def relation_paths(chapter)
      paths = []
      paths << [ "lab", chapter.dig("lab", "path") ]
      paths << [ "review_card", chapter.dig("review_card", "path") ]
      paths << [ "decision_contrast", chapter.dig("suggested_contrast", "path") ]
      paths << [ "primary_case", chapter.dig("primary_case", "path") ]
      Array(chapter["complementary_cases"]).each { |case_ref| paths << [ "complementary_case", case_ref["path"] ] }
      LINK_KEYS.each do |key|
        Array(chapter[key]).each { |path| paths << [ key.singularize, path ] }
      end
      paths
    end

    def add_directory_records(kind, pattern)
      Dir.glob(corpus_root.join(pattern)).sort.each do |path|
        relative_path = Pathname(path).relative_path_from(corpus_root).to_s
        add_record_from_path(kind, relative_path)
        add_markdown_links(relative_path, kind)
      end
    end

    def add_markdown_links(relative_path, kind)
      pathname = corpus_root.join(relative_path)
      return unless pathname.file?

      pathname.read.scan(/\]\(([^)#]+\.md)(?:#[^)]+)?\)/).flatten.each do |linked_path|
        normalized = Pathname(File.join(File.dirname(relative_path), linked_path)).cleanpath.to_s
        next unless normalized.start_with?("chapters/")

        relation = case kind
        when "capstone" then "pull_chapter"
        when "lab" then "chapter_lab"
        when "review_card" then "chapter_review"
        when "decision_contrast" then "chapter_contrast"
        else "related_chapter"
        end
        add_record_from_path("chapter", normalized)
        add_link(relative_path, normalized, relation)
      end
    rescue Errno::ENOENT
      @warnings << "could not read relationship source #{relative_path}"
    end

    def add_record_from_path(kind, relative_path, metadata: {})
      path = relative_path.to_s
      pathname = corpus_root.join(path)
      title = pathname.file? ? markdown_title(pathname) : title_from_path(path)
      checksum = pathname.file? ? Digest::SHA256.file(pathname).hexdigest : nil
      add_record(kind: kind, target: "system_design", source_path: path, title: title, source_checksum: checksum, metadata: metadata)
    end

    def add_legacy_arcade_records
      path = arcade_root.join(LEGACY_SEED_PATH)
      return unless path.file?

      checksum = Digest::SHA256.file(path).hexdigest
      parse_legacy_items(path.read).each do |item|
        item_id = item.fetch("item_id")
        add_record(
          kind: "legacy_arcade_item",
          target: "legacy",
          source_path: "#{LEGACY_SEED_PATH}##{item_id}",
          title: "Legacy Arcade item #{item_id}",
          source_checksum: checksum,
          metadata: item.merge(
            "content_origin" => "existing-english-arcade",
            "source_file" => LEGACY_SEED_PATH,
            "source_anchor" => item_id
          )
        )
      end
    end

    def parse_legacy_items(body)
      items = []
      current = nil

      body.each_line do |line|
        if line.match?(/\A  \{\s*\z/)
          items << current if current
          current = {}
        end
        next unless current

        current["item_id"] ||= line[/\bid:\s*"([^"]+)"/, 1]
        current["category"] ||= line[/\bcategory:\s*"([^"]+)"/, 1]
        current["difficulty"] ||= line[/\bdifficulty:\s*(\d+)/, 1]&.to_i
        current["blank_kinds"] ||= []
        if (kind = line[/\bkind:\s*"([^"]+)"/, 1])
          current["blank_kinds"] << kind unless current["blank_kinds"].include?(kind)
        end
      end
      items << current if current

      items.filter_map do |item|
        next if item["item_id"].blank?

        item["blank_kinds"] = item.fetch("blank_kinds").sort
        item
      end
    end

    def add_external_records
      records = @external_records || discover_external_records
      records = [ records ] if records.is_a?(Hash)
      Array(records).each do |raw|
        normalized = normalize_external_record(raw)
        if normalized
          add_record(**normalized)
          add_external_source_links(normalized[:source_id] || normalized["source_id"], normalized[:metadata] || normalized["metadata"])
        else
          @warnings << "ignored external Arcade record without target/source identity"
        end
      end
    end

    def discover_external_records
      packs = discover_pack_records
      return packs if packs.any?

      candidate = EXTERNAL_CONTENT_FILES.map { |relative| Pathname(defined?(Rails) ? Rails.root.join(relative) : relative) }.find(&:file?)
      return [] unless candidate

      case candidate.extname
      when ".yml", ".yaml"
        Array(YAML.safe_load(candidate.read, aliases: true))
      when ".json"
        Array(JSON.parse(candidate.read))
      else
        @warnings << "Ruby external content requires explicit external_records: #{candidate}"
        []
      end
    rescue JSON::ParserError, Psych::Exception => error
      @warnings << "could not read external Arcade content: #{error.message}"
      []
    end

    # The content handoff may ship one YAML file per target.  Keep this reader
    # deliberately schema-light: PackValidator owns the authoring contract;
    # this adapter only projects each item to a stable source anchor.
    def discover_pack_records
      directory = if ENV["ENGLISH_ARCADE_PACK_PATH"].present?
        Pathname(ENV.fetch("ENGLISH_ARCADE_PACK_PATH"))
      elsif arcade_root.join(PACK_DIRECTORY).directory?
        arcade_root.join(PACK_DIRECTORY)
      elsif defined?(Rails) && arcade_root == Pathname(default_arcade_root).expand_path
        Rails.root.join(PACK_DIRECTORY)
      end
      return [] unless directory
      return [] unless directory.directory?

      directory.glob("*.{yml,yaml}").sort.flat_map do |path|
        pack = YAML.safe_load(path.read, aliases: true)
        checksum = Digest::SHA256.file(path).hexdigest
        targets = if pack.is_a?(Hash) && pack["targets"].is_a?(Array)
          pack["targets"]
        elsif pack.is_a?(Hash) && pack["target"].is_a?(Hash)
          [ pack ]
        else
          []
        end

        targets.flat_map do |target_pack|
          target = target_pack.dig("target", "key") || target_pack["key"]
          next [] if target.blank?

          Array(target_pack["items"]).filter_map do |item|
            next unless item.is_a?(Hash) && item["id"].present?

            {
              "source_id" => "packs/#{target}/#{item.fetch("id")}",
              "target" => target,
              "kind" => "interview_pack",
              "source_path" => "#{PACK_DIRECTORY}/#{path.basename}##{item.fetch("id")}",
              "source_checksum" => checksum,
              "title" => item["topic"].presence || item.fetch("id").tr("-", " ").titleize,
              "metadata" => item.merge(
                "pack_target_label" => target_pack.dig("target", "label"),
                "corpus_links" => target_pack["corpus_links"] || pack["corpus_links"],
                "content_origin" => "english-arcade-pack"
              )
            }
          end
        end
      end
    rescue Psych::Exception, Errno::ENOENT => error
      @warnings << "could not read English Arcade packs: #{error.message}"
      []
    end

    def normalize_external_record(raw)
      value = raw.respond_to?(:to_h) ? raw.to_h : {}
      target = normalize_target(value["target"] || value[:target])
      source_id = value["source_id"] || value[:source_id] || value["id"] || value[:id]
      return if target.blank? || source_id.blank?

      source_id = "#{ARCADE_SOURCE_ID_PREFIX}:#{source_id}" unless source_id.to_s.start_with?("#{ARCADE_SOURCE_ID_PREFIX}:")
      source_path = value["source_path"] || value[:source_path] || "content/#{target}/#{source_id.to_s.split(":").last}.yml"
      metadata = value["metadata"] || value[:metadata] || {}
      metadata["sources"] ||= value["sources"] || value[:sources]
      metadata["corpus_links"] ||= value["corpus_links"] || value[:corpus_links]
      %w[prompt context answer distractors feedback rephrase].each do |key|
        metadata[key] ||= value[key] || value[key.to_sym]
      end
      metadata["answer"] ||= metadata["best_answer"] || value["best_answer"] || value[:best_answer]

      {
        kind: value["kind"] || value[:kind] || "interview_pack",
        target: target,
        source_path: source_path,
        title: value["title"] || value[:title] || source_id.to_s.split(":").last.tr("-", " ").titleize,
        source_checksum: value["source_checksum"] || value[:source_checksum],
        metadata: metadata.merge("content_origin" => "cockpit-english-arcade")
      }.tap { |normalized| normalized[:source_id] = source_id }
    end

    def add_record(kind:, target:, source_path:, title:, metadata: {}, source_checksum: nil, source_id: nil)
      path = source_path.to_s
      stable_id = if source_id
        source_id
      elsif path.start_with?("#{LEGACY_SEED_PATH}#")
        self.class.arcade_source_id_for(path.split("#", 2).last)
      elsif path.start_with?("#{LEGACY_SEED_PATH}") || path.start_with?("content/")
        "#{ARCADE_SOURCE_ID_PREFIX}:#{path}"
      else
        self.class.source_id_for(path)
      end
      key = stable_id.to_s
      existing = @records[key]
      merged_metadata = (existing&.metadata || {}).merge(stringify_keys(metadata))
      record = Record.new(
        source_id: key,
        target: normalize_target(target),
        kind: kind.to_s,
        title: title.to_s,
        source_path: path,
        source_checksum: source_checksum || existing&.source_checksum,
        metadata: merged_metadata,
        search_text: build_search_text(key, title, path, merged_metadata)
      )
      @records[key] = record
    end

    def add_link(source_path, target_path, relation)
      source_id = source_path.to_s.start_with?(ARCADE_SOURCE_ID_PREFIX) ? source_path.to_s : self.class.source_id_for(source_path)
      target_id = target_path.to_s.start_with?(ARCADE_SOURCE_ID_PREFIX) ? target_path.to_s : self.class.source_id_for(target_path)
      @links << Link.new(source_id: source_id, target_source_id: target_id, relation: relation.to_s, target_path: target_path.to_s)
    end

    def add_external_source_links(source_id, metadata)
      references = metadata.is_a?(Hash) ? (metadata["sources"] || metadata[:sources] || metadata["corpus_links"] || metadata[:corpus_links]) : nil
      references = references.is_a?(Array) ? references : [ references ]
      references.each do |reference|
        next unless reference.is_a?(Hash)
        repository = reference["repo"] || reference[:repo] || reference["repository"] || reference[:repository]
        next unless repository.to_s == SOURCE_ID_PREFIX

        path = reference["path"] || reference[:path]
        next if path.to_s.empty?

        add_link(source_id, path, "pack_source")
      end
    end

    def unique_links
      @links.uniq { |link| [ link.source_id, link.target_source_id, link.relation ] }
    end

    def attach_links_to_metadata
      links_by_source = unique_links.group_by(&:source_id)
      links_by_source.each do |source_id, links|
        record = @records[source_id]
        next unless record

        related = links.map { |link| link.target_source_id }.uniq
        record.metadata["english_arcade_links"] = links.map(&:to_h)
        record.metadata["related_source_ids"] = related
        record.search_text = build_search_text(record.source_id, record.title, record.source_path, record.metadata)
      end
    end

    def persist_study_document_metadata(records, links)
      return 0 unless @persist && defined?(StudyDocument)

      persisted = 0
      records.each do |record|
        document = StudyDocument.find_by(source_path: record.source_path)
        next unless document

        metadata = document.metadata.to_h.deep_dup
        metadata["source_id"] ||= record.source_id
        metadata["english_arcade"] = {
          "source_id" => record.source_id,
          "target" => record.target,
          "kind" => record.kind,
          "source_path" => record.source_path,
          "links" => links.select { |link| link.source_id == record.source_id }.map(&:to_h)
        }
        next if metadata == document.metadata

        document.update!(metadata: metadata)
        persisted += 1
      end
      persisted
    end

    def safe_yaml(path)
      return {} unless path.file?

      YAML.safe_load(path.read, aliases: true) || {}
    rescue Psych::Exception => error
      @warnings << "could not read #{path}: #{error.message}"
      {}
    end

    def markdown_title(path)
      path.each_line do |line|
        return line.delete_prefix("# ").strip if line.start_with?("# ")
      end
      title_from_path(path.to_s)
    end

    def title_from_path(path)
      File.basename(path, ".md").sub(/\A\d{2}-/, "").tr("-", " ").split.map(&:capitalize).join(" ")
    end

    def kind_for_path(path)
      case path.to_s
      when %r{\Alabs/} then "lab"
      when %r{\Areviews/cards/} then "review_card"
      when %r{\Adecision-contrasts/} then "decision_contrast"
      when %r{\Acapstones/} then "capstone"
      when %r{\Achapters/} then "chapter"
      when %r{\Areal-world-cases/} then "real_world_case"
      when %r{\Asimulation-labs/} then "simulation_lab"
      else "reference_document"
      end
    end

    def normalize_target(value)
      normalized = value.to_s.strip.downcase.tr("-", "_")
      normalized = "system_design" if normalized == "systemdesign"
      normalized.presence
    end

    def build_search_text(source_id, title, path, metadata)
      values = [ source_id, title, path ] + metadata.values.flat_map { |value| value.is_a?(Array) ? value : value }
      values.flatten.compact.map(&:to_s).join(" ").downcase
    end

    def stringify_keys(value)
      return value.to_h.transform_keys(&:to_s) if value.respond_to?(:to_h)

      value
    end

    def default_corpus_root
      configured = ENV["STUDY_CONTENT_PATH"]
      return configured if configured.present?

      defined?(Rails) ? Rails.root.join("../system-design-estudos") : Pathname("../system-design-estudos")
    end

    def default_arcade_root
      configured = ENV["ENGLISH_ARCADE_PATH"]
      return configured if configured.present?

      defined?(Rails) ? Rails.root.join("../../english-arcade") : Pathname("../../english-arcade")
    end
  end
end
