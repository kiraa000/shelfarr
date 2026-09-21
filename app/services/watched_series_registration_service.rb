# frozen_string_literal: true

class WatchedSeriesRegistrationService
  class << self
    def register!(user:, collection_source:, collection_id:, title:, book_types:, language: nil)
      return unless collection_source.to_s == "hardcover"
      return unless SettingsService.get(:hardcover_series_watch_enabled, default: true)

      normalized_types = Array(book_types).map(&:to_s).select { |type| type == "audiobook" }.uniq
      return if normalized_types.empty?

      watched = WatchedSeries.find_or_initialize_by(
        user: user,
        collection_source: "hardcover",
        collection_id: collection_id.to_s
      )

      watched.title = title.to_s.presence || watched.title || "Hardcover Series #{collection_id}"
      watched.book_types = (watched.normalized_book_types + normalized_types).uniq
      watched.language = language.presence || watched.language
      watched.enabled = true
      watched.last_error = nil
      watched.save!
      watched
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def backfill_existing!
      return 0 unless SettingsService.get(:hardcover_series_watch_enabled, default: true)

      rows = Request
        .joins(:book)
        .where(collection_source: "hardcover")
        .where.not(collection_id: [ nil, "" ])
        .where.not(collection_title: [ nil, "" ])
        .group(:user_id, :collection_id, :collection_title)
        .pluck(:user_id, :collection_id, :collection_title)

      count = 0
      rows.each do |user_id, collection_id, collection_title|
        user = User.active.find_by(id: user_id)
        next unless user
        next if WatchedSeries.exists?(
          user_id: user_id,
          collection_source: "hardcover",
          collection_id: collection_id.to_s
        )

        types = Request
          .joins(:book)
          .where(
            user_id: user_id,
            collection_source: "hardcover",
            collection_id: collection_id
          )
          .distinct
          .pluck("books.book_type")
          .filter_map { |value| Book.book_types.key(value) }
          .map(&:to_s)
          .select { |type| type == "audiobook" }

        next if types.empty?

        register!(
          user: user,
          collection_source: "hardcover",
          collection_id: collection_id,
          title: collection_title,
          book_types: types
        )
        count += 1
      end

      count
    end
  end
end
