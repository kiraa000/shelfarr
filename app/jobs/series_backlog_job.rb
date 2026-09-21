# frozen_string_literal: true

class SeriesBacklogJob < ApplicationJob
  queue_as :default

  def perform(limit: SeriesBacklogService::DEFAULT_DAILY_LIMIT)
    state = SeriesBacklogService.run(limit: limit)
    counts = state.fetch("entries").group_by { |entry| entry["status"] }.transform_values(&:count)
    Rails.logger.info "[SeriesBacklogJob] Backlog run complete: #{counts.inspect}"
  end
end
