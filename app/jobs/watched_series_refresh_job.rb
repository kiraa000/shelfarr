# frozen_string_literal: true

class WatchedSeriesRefreshJob < ApplicationJob
  queue_as :default

  retry_on MetadataCollectionService::Error, wait: :polynomially_longer, attempts: 3

  def perform
    WatchedSeriesRegistrationService.backfill_existing!

    WatchedSeries.enabled.includes(:user).find_each do |watched|
      next if watched.user.deleted?

      begin
        result = WatchedSeriesRefreshService.call(watched)
        Rails.logger.info(
          "[WatchedSeriesRefreshJob] #{watched.title} (#{watched.collection_id}): "           "created=#{result.created_requests.size} skipped=#{result.skipped_items} errors=#{result.errors.size}"
        )
      rescue MetadataCollectionService::Error
        raise
      rescue StandardError => e
        Rails.logger.warn(
          "[WatchedSeriesRefreshJob] #{watched.title} (#{watched.collection_id}) failed: #{e.class}: #{e.message}"
        )
      end
    end
  end
end
