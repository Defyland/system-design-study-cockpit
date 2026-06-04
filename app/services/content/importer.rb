module Content
  class Importer
    def initialize(source:, parser: MarkdownParser.new)
      @source = source
      @parser = parser
    end

    def call
      imported = @source.documents.map { |document| import_document(document) }
      ensure_progress_for(imported)
      imported
    end

    private

    def import_document(document)
      parsed = @parser.parse(**document)
      study_document = StudyDocument.find_or_initialize_by(kind: parsed.fetch(:kind), slug: parsed.fetch(:slug))
      changed = study_document.new_record? || study_document.body_checksum != parsed.fetch(:body_checksum)

      study_document.assign_attributes(parsed.slice(
        :title,
        :source_path,
        :phase,
        :position,
        :body_markdown,
        :body_checksum,
        :metadata
      ))

      StudyDocument.transaction do
        study_document.save!

        if changed
          study_document.study_blocks.destroy_all
          study_document.checkpoints.destroy_all
          parsed.fetch(:blocks).each { |block| study_document.study_blocks.create!(block) }
          parsed.fetch(:checkpoints).each { |checkpoint| study_document.checkpoints.create!(checkpoint) }
        end
      end

      study_document
    end

    def ensure_progress_for(documents)
      documents.each do |document|
        document.create_study_progress! unless document.study_progress
      end
    end
  end
end
