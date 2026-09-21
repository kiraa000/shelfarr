# frozen_string_literal: true

require "test_helper"

class WatchedSeriesRegistrationServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    SettingsService.set(:hardcover_series_watch_enabled, true)
  end

  test "registers an exact Hardcover series id for audiobooks only" do
    watched = WatchedSeriesRegistrationService.register!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "987",
      title: "Test Series",
      book_types: [ "audiobook" ]
    )

    WatchedSeriesRegistrationService.register!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "987",
      title: "Test Series",
      book_types: [ "ebook" ]
    )

    assert_equal "987", watched.reload.collection_id
    assert_equal [ "audiobook" ], watched.normalized_book_types
    assert watched.enabled?
  end

  test "does not watch non-Hardcover collections" do
    assert_no_difference "WatchedSeries.count" do
      result = WatchedSeriesRegistrationService.register!(
        user: @user,
        collection_source: "comic_vine",
        collection_id: "4050-99",
        title: "Saga",
        book_types: [ "comicbook" ]
      )
      assert_nil result
    end
  end
end
