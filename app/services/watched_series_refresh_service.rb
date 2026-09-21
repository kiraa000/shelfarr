# frozen_string_literal: true

class WatchedSeriesRefreshService
  Result = Data.define(:created_requests, :skipped_items, :errors)

  class << self
    def call(watched_series)
      new(watched_series).call
    end
  end

  def initialize(watched_series)
    @watched_series = watched_series
  end

  def call
    return Result.new(created_requests: [], skipped_items: 0, errors: []) unless watched_series.enabled?

    items = MetadataCollectionService.expand(
      source: watched_series.collection_source,
      collection_id: watched_series.collection_id,
      collection_title: watched_series.title,
      content_kind: "book"
    )

    created_requests = []
    errors = []
    skipped_items = 0
    work_ids = items.flat_map { |item| [ item.work_id, *Array(item.source_work_ids) ] }
    existing_lookup = Book.preload_by_work_ids(work_ids)

    items.each do |item|
      watched_series.normalized_book_types.each do |book_type|
        item_work_ids = [ item.work_id, *Array(item.source_work_ids) ].compact_blank.uniq

        existing_book = Book.find_in_lookup(existing_lookup, item_work_ids, book_type: book_type)
        if existing_book
          repair_series_metadata(existing_book, item)
          rearm_exhausted_retry(existing_book)
          skipped_items += 1
          next
        end

        metadata = item.metadata_attrs.merge(
          request_scope: "single",
          collection_source: watched_series.collection_source,
          collection_id: watched_series.collection_id,
          collection_title: watched_series.title
        )

        result = RequestCreationService.call(
          user: watched_series.user,
          work_id: item.work_id,
          source_work_ids: item.source_work_ids,
          book_types: [ book_type ],
          metadata_attrs: metadata,
          language: watched_series.language,
          origin: {
            created_via: "api",
            external_source: "series_watch"
          }
        )

        created_requests.concat(result.created_requests)
        errors.concat(result.errors)

        result.created_requests.each do |request|
          Book.work_ids_for(request.book).each do |work_id|
            existing_lookup[work_id][request.book.book_type] = request.book
          end
        end
      end
    end

    now = Time.current
    attributes = {
      last_checked_at: now,
      last_error: errors.presence&.join("; ")
    }
    attributes[:last_success_at] = now if errors.empty?
    watched_series.update!(attributes)

    Result.new(
      created_requests: created_requests,
      skipped_items: skipped_items,
      errors: errors
    )
  rescue StandardError => e
    if watched_series.persisted?
      watched_series.update_columns(
        last_checked_at: Time.current,
        last_error: "#{e.class}: #{e.message}",
        updated_at: Time.current
      )
    end
    raise
  end

  private

  attr_reader :watched_series

  def repair_series_metadata(book, item)
    attrs = item.metadata_attrs
    updates = {}
    updates[:series] = attrs[:series] if book.series.blank? && attrs[:series].present?
    updates[:series_position] = attrs[:series_position] if book.series_position.blank? && attrs[:series_position].present?
    return false if updates.empty?

    book.update!(updates)
    Rails.logger.info(
      "[WatchedSeriesRefreshService] Repaired series metadata for book ##{book.id}: #{updates.inspect}"
    )
    true
  end

  def rearm_exhausted_retry(book)
    request = book.requests
      .where(status: :not_found, attention_needed: true)
      .order(updated_at: :desc)
      .detect { |candidate| candidate.issue_description.to_s.start_with?("Maximum retry attempts") }
    return false unless request

    request.update!(retry_count: 0)
    request.retry_now!
    Rails.logger.info(
      "[WatchedSeriesRefreshService] Re-armed exhausted request ##{request.id} for watched series #{watched_series.title}"
    )
    true
  end
end
