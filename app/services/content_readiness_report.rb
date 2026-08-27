require "yaml"
require "pathname"
require_relative "../../lib/english_arcade/pack_validator"
require_relative "../../lib/english_arcade/schema"

class ContentReadinessReport
  HEALTHY_STATUSES = %w[ok warning].freeze
  ARCADE_TARGETS = EnglishArcade::Schema::TARGETS.freeze
  CANONICAL_ARCADE_TARGETS = EnglishArcade::Schema::CANONICAL_TARGETS.freeze
  ELECTIVE_ARCADE_TARGETS = EnglishArcade::Schema::ELECTIVE_TARGETS.freeze
  PACK_REQUIRED_FIELDS = ((EnglishArcade::Schema::REQUIRED_ITEM_KEYS & %w[prompt context distractors feedback rephrase]) + [ "best_answer" ]).freeze

  def initialize(
    relation: StudyDocument.all,
    sync_runs: ContentSyncRun.all,
    production: Rails.env.production?,
    arcade_pack_directory: Rails.root.join("db/seeds/english_arcade")
  )
    @relation = relation
    @sync_runs = sync_runs
    @production = production
    @arcade_pack_directory = Pathname(arcade_pack_directory)
  end

  def ok?
    status == "ok"
  end

  def available?
    HEALTHY_STATUSES.include?(status)
  end

  def warning?
    status == "warning"
  end

  def as_json(*)
    {
      status: status,
      adapter: adapter,
      study_documents: study_document_count,
      reference_documents: reference_document_count,
      side_tracks: side_track_count,
      english_arcade_pack_readiness: arcade_pack_readiness,
      backend_interview_foundations_present: backend_interview_foundations_present?,
      content_bootstrapped: content_bootstrapped?,
      latest_sync_status: latest_sync&.status,
      latest_sync_mode: redacted_sync_mode,
      # Health output is an aggregate/readiness boundary. Never expose source
      # locations, paths, checksums, claims, or error prose through it.
      latest_sync_location: latest_sync.present? ? "configured" : nil,
      latest_sync_started_at: latest_sync&.started_at,
      latest_sync_finished_at: latest_sync&.finished_at,
      latest_sync_document_count: latest_sync&.document_count,
      latest_sync_error: latest_sync_failed? ? "sync_failed" : nil,
      last_successful_sync_at: last_successful_sync&.finished_at,
      last_successful_sync_document_count: last_successful_sync&.document_count
    }
  end

  def http_status
    available? ? :ok : :service_unavailable
  end

  private

  def adapter
    ActiveRecord::Base.connection_db_config.adapter
  end

  def status
    return "degraded" unless adapter == "postgresql"
    return "degraded" unless content_bootstrapped?
    return "warning" unless arcade_pack_readiness.fetch("ready")
    return "warning" unless sync_observed?
    return "warning" if latest_sync_failed?

    "ok"
  end

  def backend_interview_foundations_present?
    @relation.side_track_overview.exists?(slug: "backend-interview-foundations")
  end

  def content_bootstrapped?
    study_document_count.positive? && backend_interview_foundations_present?
  end

  def sync_observed?
    return true unless @production

    last_successful_sync.present?
  end

  def latest_sync_failed?
    latest_sync&.failed?
  end

  def redacted_sync_mode
    return unless latest_sync

    mode = latest_sync.source_mode.to_s
    %w[github filesystem].include?(mode) ? mode : "configured"
  end

  def arcade_pack_readiness
    return @arcade_pack_readiness if defined?(@arcade_pack_readiness)

    directory = @arcade_pack_directory
    packs = {}
    if directory.directory?
      Dir.glob(directory.join("*.yml")).sort.each do |path|
        target = File.basename(path, ".yml").tr("-", "_")
        next unless ARCADE_TARGETS.include?(target)

        payload = YAML.safe_load_file(path, aliases: false) || {}
        items = Array(payload["items"])
        validator = EnglishArcade::PackValidator.new(payload, strict: true)
        validator.valid?
        packs[target] = {
          "item_count" => items.length,
          "card_count" => Array(payload["cards"]).length,
          "missing_fields" => PACK_REQUIRED_FIELDS.select { |field| items.any? { |item| !item.is_a?(Hash) || item[field].blank? } },
          "validation_error_count" => validator.errors.size
        }
      end
    end
    missing_targets = ARCADE_TARGETS - packs.keys
    target_ready = packs.values.all? do |pack|
      pack.fetch("item_count") >= EnglishArcade::Schema::PUBLISHABLE_ITEMS_PER_TARGET &&
        pack.fetch("card_count").between?(EnglishArcade::Schema::MINIMUM_CARDS_PER_TARGET, EnglishArcade::Schema::MAXIMUM_CARDS_PER_TARGET) &&
        pack.fetch("missing_fields").empty? &&
        pack.fetch("validation_error_count").zero?
    end
    @arcade_pack_readiness = {
      "minimum_items_per_target" => EnglishArcade::Schema::PUBLISHABLE_ITEMS_PER_TARGET,
      "target_count" => packs.length,
      "item_count" => packs.values.sum { |pack| pack.fetch("item_count") },
      "card_count" => packs.values.sum { |pack| pack.fetch("card_count") },
      "canonical_target_count" => packs.keys.count { |target| CANONICAL_ARCADE_TARGETS.include?(target) },
      "canonical_item_count" => packs.sum { |target, pack| CANONICAL_ARCADE_TARGETS.include?(target) ? pack.fetch("item_count") : 0 },
      "canonical_card_count" => packs.sum { |target, pack| CANONICAL_ARCADE_TARGETS.include?(target) ? pack.fetch("card_count") : 0 },
      "targets" => packs,
      "missing_targets" => missing_targets,
      "ready" => missing_targets.empty? && target_ready,
      "elective_targets" => ELECTIVE_ARCADE_TARGETS
    }
  rescue Psych::Exception, Errno::ENOENT, TypeError
    @arcade_pack_readiness = {
      "minimum_items_per_target" => EnglishArcade::Schema::PUBLISHABLE_ITEMS_PER_TARGET,
      "target_count" => 0,
      "item_count" => 0,
      "card_count" => 0,
      "canonical_target_count" => 0,
      "canonical_item_count" => 0,
      "canonical_card_count" => 0,
      "targets" => {},
      "missing_targets" => ARCADE_TARGETS,
      "ready" => false,
      "elective_targets" => ELECTIVE_ARCADE_TARGETS
    }
  end

  def latest_sync
    @latest_sync ||= @sync_runs.latest_first.first
  end

  def last_successful_sync
    @last_successful_sync ||= @sync_runs.succeeded.latest_first.first
  end

  def study_document_count
    @study_document_count ||= @relation.count
  end

  def reference_document_count
    @reference_document_count ||= @relation.reference_document.count
  end

  def side_track_count
    @side_track_count ||= @relation.side_track_overview.count
  end
end
