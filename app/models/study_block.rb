class StudyBlock < ApplicationRecord
  enum :kind, {
    heading: "heading",
    paragraph: "paragraph",
    list: "list",
    code: "code",
    other: "other"
  }

  belongs_to :study_document

  validates :kind, :content_markdown, presence: true
  validates :position, numericality: { greater_than: 0 }, uniqueness: { scope: :study_document_id }
end
