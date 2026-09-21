# frozen_string_literal: true

require "pathname"

class AudiobookshelfMetadataSyncJob < ApplicationJob
  queue_as :default

  RETRY_DELAYS = [15, 30, 60, 120, 180].freeze

  def perform(book_id, attempt: 0)
    return unless LibraryPlatformClient.active_platform == "audiobookshelf"
    return unless AudiobookshelfClient.configured?

    book = Book.find_by(id: book_id)
    return unless book&.file_path.present?

    library_id = SettingsService.library_id_for_book(book)
    return unless library_id.present?

    relative_path = relative_library_path(book)

    item = AudiobookshelfClient.find_item_by_relative_path(
      library_id,
      relative_path
    )

    unless item
      retry_later(book_id, attempt, "Audiobookshelf item not visible yet")
      return
    end

    AudiobookshelfClient.update_book_metadata(item.fetch("id"), book)

    Rails.logger.info(
      "[AudiobookshelfMetadataSyncJob] Updated ABS metadata for book ##{book.id}"
    )

    AudiobookshelfLibrarySyncJob.schedule_post_scan_refresh!
  rescue AudiobookshelfClient::Error => e
    retry_later(book_id, attempt, e.message)
  rescue ArgumentError => e
    Rails.logger.warn(
      "[AudiobookshelfMetadataSyncJob] Cannot map book ##{book_id}: #{e.message}"
    )
  end

  private

  def retry_later(book_id, attempt, reason)
    delay = RETRY_DELAYS[attempt]

    unless delay
      Rails.logger.warn(
        "[AudiobookshelfMetadataSyncJob] Giving up on book ##{book_id}: #{reason}"
      )
      return
    end

    Rails.logger.info(
      "[AudiobookshelfMetadataSyncJob] Retrying book ##{book_id} in #{delay}s: #{reason}"
    )

    self.class
      .set(wait: delay.seconds)
      .perform_later(book_id, attempt: attempt + 1)
  end

  def relative_library_path(book)
    root =
      if book.audiobook?
        SettingsService.get(:audiobook_output_path, default: "/audiobooks")
      elsif book.comicbook?
        SettingsService.get(:comicbook_output_path, default: "/comics")
      else
        SettingsService.get(:ebook_output_path, default: "/ebooks")
      end

    root_path = Pathname(root).expand_path
    book_path = Pathname(book.file_path).expand_path
    relative = book_path.relative_path_from(root_path)

    if relative.each_filename.any? { |part| part == ".." }
      raise ArgumentError, "book path is outside configured output root"
    end

    relative.to_s.tr("\\", "/")
  end
end
