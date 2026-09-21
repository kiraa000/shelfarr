# frozen_string_literal: true

class WatchedSeriesController < ApplicationController
  before_action :set_watched_series, only: [ :update, :refresh ]

  def index
    @watched_series = Current.user.watched_series.order(Arel.sql("LOWER(title) ASC"))
  end

  def update
    enabled = ActiveModel::Type::Boolean.new.cast(params.require(:watched_series).fetch(:enabled))
    @watched_series.update!(enabled: enabled)

    redirect_to watched_series_index_path,
      notice: "#{@watched_series.title} is now #{enabled ? 'watched' : 'not watched'}."
  end

  def refresh
    unless @watched_series.enabled?
      redirect_to watched_series_index_path, alert: "Enable this series before checking it."
      return
    end

    result = WatchedSeriesRefreshService.call(@watched_series)
    message = "Checked #{@watched_series.title}: #{result.created_requests.size} new request(s)."
    message += " #{result.errors.size} item(s) had errors." if result.errors.any?

    redirect_to watched_series_index_path, notice: message
  rescue MetadataCollectionService::Error => e
    redirect_to watched_series_index_path, alert: "Could not refresh #{@watched_series.title}: #{e.message}"
  end

  private

  def set_watched_series
    @watched_series = Current.user.watched_series.find(params[:id])
  end
end
