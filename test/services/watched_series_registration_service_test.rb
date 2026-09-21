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

  test "register can explicitly disable a series so backfill does not opt it back in" do
    watched = WatchedSeriesRegistrationService.register!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "987",
      title: "Test Series",
      book_types: [ "audiobook" ],
      enabled: false
    )

    assert_not watched.enabled?
  end

  test "backfills an existing Hardcover audiobook collection request as watched" do
    book = Book.create!(
      title: "Existing Series Book",
      book_type: :audiobook,
      hardcover_id: "123"
    )
    Request.create!(
      user: @user,
      book: book,
      status: :completed,
      request_scope: "collection",
      collection_source: "hardcover",
      collection_id: "29395",
      collection_title: "The Primal Hunter"
    )

    assert_difference "WatchedSeries.count", 1 do
      assert_equal 1, WatchedSeriesRegistrationService.backfill_existing!
    end

    watched = WatchedSeries.last
    assert_equal "29395", watched.collection_id
    assert_equal "The Primal Hunter", watched.title
    assert_equal [ "audiobook" ], watched.normalized_book_types
    assert watched.enabled?
  end

  test "backfill does not re-enable a disabled watch" do
    watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "987",
      title: "Test Series",
      book_types: [ "audiobook" ],
      enabled: false
    )
    book = Book.create!(
      title: "Existing Series Book",
      book_type: :audiobook,
      hardcover_id: "123"
    )
    Request.create!(
      user: @user,
      book: book,
      status: :completed,
      request_scope: "collection",
      collection_source: "hardcover",
      collection_id: "987",
      collection_title: "Test Series"
    )

    WatchedSeriesRegistrationService.backfill_existing!

    assert_not watched.reload.enabled?
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
