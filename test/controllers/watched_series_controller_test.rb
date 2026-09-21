# frozen_string_literal: true

require "test_helper"

class WatchedSeriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_path, params: {
      username: @user.username,
      password: "password"
    }
    @watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "29395",
      title: "The Primal Hunter",
      book_types: [ "audiobook" ],
      enabled: true
    )
  end

  test "index lists the current user's watched series" do
    get watched_series_index_path

    assert_response :success
    assert_includes response.body, "The Primal Hunter"
    assert_includes response.body, "Watching"
  end

  test "user can stop and start watching a series" do
    patch watched_series_path(@watched), params: {
      watched_series: { enabled: "false" }
    }

    assert_redirected_to watched_series_index_path
    assert_not @watched.reload.enabled?

    patch watched_series_path(@watched), params: {
      watched_series: { enabled: "true" }
    }

    assert @watched.reload.enabled?
  end
end
