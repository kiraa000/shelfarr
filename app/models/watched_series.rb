# frozen_string_literal: true

class WatchedSeries < ApplicationRecord
  belongs_to :user

  scope :enabled, -> { where(enabled: true) }

  validates :collection_source, presence: true
  validates :collection_id, presence: true
  validates :title, presence: true
  validate :book_types_are_supported

  def normalized_book_types
    Array(book_types).map(&:to_s).select { |type| Book.book_types.key?(type) }.uniq
  end

  private

  def book_types_are_supported
    invalid = Array(book_types).map(&:to_s).reject { |type| Book.book_types.key?(type) }
    errors.add(:book_types, "contains unsupported types: #{invalid.join(', ')}") if invalid.any?
    errors.add(:book_types, "must include at least one type") if normalized_book_types.empty?
  end
end
