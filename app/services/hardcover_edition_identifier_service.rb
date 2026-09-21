# frozen_string_literal: true

class HardcoverEditionIdentifierService
  Result = Data.define(:edition_id, :isbn, :asin)

  AUDIOBOOK_FORMAT = /\b(audio\s*book|audible)\b/i

  class << self
    def call(book)
      return empty_result unless book.audiobook?
      return empty_result if book.hardcover_id.blank?

      candidates = HardcoverClient
        .book_editions(book.hardcover_id)
        .select { |edition| audiobook_edition?(edition) }

      return empty_result if candidates.empty?

      best_score = candidates.map { |edition| selection_score(book, edition) }.max
      finalists = candidates.select do |edition|
        selection_score(book, edition) == best_score
      end

      return empty_result if conflicting_identifiers?(finalists)

      selected = finalists.max_by do |edition|
        [
          normalized_asin(edition.asin).present? ? 1 : 0,
          valid_isbn(edition).present? ? 1 : 0,
          -edition.id.to_i
        ]
      end

      Result.new(
        edition_id: selected.id,
        isbn: valid_isbn(selected),
        asin: normalized_asin(selected.asin)
      )
    end

    private

    def audiobook_edition?(edition)
      explicit_audiobook_format?(edition) ||
        edition.audio_seconds.to_i.positive?
    end

    def explicit_audiobook_format?(edition)
      edition.edition_format.to_s.match?(AUDIOBOOK_FORMAT)
    end

    def selection_score(book, edition)
      [
        explicit_audiobook_format?(edition) ? 1 : 0,
        edition.audio_seconds.to_i.positive? ? 1 : 0,
        normalized_title(edition.title) == normalized_title(book.title) ? 1 : 0,
        edition.release_date.present? ? 1 : 0
      ]
    end

    def conflicting_identifiers?(editions)
      asins = editions.filter_map do |edition|
        normalized_asin(edition.asin)
      end.uniq

      isbns = editions.filter_map do |edition|
        valid_isbn(edition)
      end.uniq

      asins.many? || isbns.many?
    end

    def normalized_asin(value)
      value.to_s.strip.upcase.presence
    end

    def valid_isbn(edition)
      if edition.isbn_13_valid == true && edition.isbn_13.present?
        edition.isbn_13.to_s.strip
      elsif edition.isbn_10_valid == true && edition.isbn_10.present?
        edition.isbn_10.to_s.strip
      end
    end

    def normalized_title(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def empty_result
      Result.new(
        edition_id: nil,
        isbn: nil,
        asin: nil
      )
    end
  end
end
