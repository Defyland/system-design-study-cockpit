# frozen_string_literal: true

require "yaml"
require_relative "schema"
require_relative "pack_validator"

module EnglishArcade
  # Reads the YAML content packs from disk and returns validated hashes.
  #
  # Loading is separated from the Rails-facing library so the packs can be
  # validated from a plain Ruby process in CI without a database.
  class PackLoader
    PACK_EXTENSION = ".yml"

    class MissingPackError < StandardError; end

    attr_reader :directory

    def initialize(directory)
      @directory = directory.to_s
    end

    # Returns { "dsa" => pack_hash, ... } for every target in canonical order.
    def load_all(validate: true, strict: true)
      Schema::TARGETS.to_h do |target|
        [ target, load(target, validate: validate, strict: strict) ]
      end
    end

    def load(target, validate: true, strict: true)
      path = path_for(target)
      raise MissingPackError, "No English Arcade pack at #{path}" unless File.file?(path)

      pack = read(path)
      PackValidator.validate!(pack, strict: strict) if validate
      pack
    end

    def path_for(target)
      File.join(directory, "#{target.to_s.tr("_", "-")}#{PACK_EXTENSION}")
    end

    private

    def read(path)
      YAML.safe_load_file(path, permitted_classes: [], aliases: false)
    end
  end
end
