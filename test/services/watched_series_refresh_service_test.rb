# frozen_string_literal: true

require "test_helper"

class WatchedSeriesRefreshServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    clear_enqueued_jobs
  end

  test "requests only series books Shelfarr has never seen and includes side material" do
    watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "987",
      title: "Test Series",
      book_types: [ "audiobook" ]
    )

    Book.create!(
      title: "Existing Book",
      author: "Series Author",
      book_type: :audiobook,
      hardcover_id: "111"
    )

    items = [
      MetadataCollectionService::Item.new(
        work_id: "hardcover:111",
        source_work_ids: [ "hardcover:111" ],
        metadata_attrs: {
          title: "Existing Book",
          author: "Series Author",
          series: "Test Series",
          series_position: "1"
        }
      ),
      MetadataCollectionService::Item.new(
        work_id: "hardcover:222",
        source_work_ids: [ "hardcover:222" ],
        metadata_attrs: {
          title: "Side Story",
          author: "Series Author",
          series: "Test Series",
          series_position: "1.5"
        }
      )
    ]

    result = MetadataCollectionService.stub(:expand, items) do
      MetadataService.stub(:book_details, nil) do
        assert_difference [ "Book.count", "Request.count" ], 1 do
          WatchedSeriesRefreshService.call(watched)
        end
      end
    end

    assert_equal 1, result.created_requests.size
    assert_equal 1, result.skipped_items
    request = result.created_requests.first
    assert_equal "222", request.book.hardcover_id
    assert_equal "1.5", request.book.series_position
    assert_equal "Test Series", request.collection_title
    assert_equal "series_watch", request.external_source
    assert_equal "api", request.created_via
    assert watched.reload.last_success_at.present?
  end

  test "re-arms requests that exhausted normal not-found retries" do
    watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "987",
      title: "Test Series",
      book_types: [ "audiobook" ]
    )
    book = Book.create!(
      title: "Future Book",
      book_type: :audiobook,
      hardcover_id: "444"
    )
    request = Request.create!(
      user: @user,
      book: book,
      status: :not_found,
      retry_count: 11,
      attention_needed: true,
      issue_description: "Maximum retry attempts (10) exceeded. Manual intervention required."
    )
    item = MetadataCollectionService::Item.new(
      work_id: "hardcover:444",
      source_work_ids: [ "hardcover:444" ],
      metadata_attrs: {
        title: "Future Book",
        series: "Test Series",
        series_position: "3"
      }
    )

    MetadataCollectionService.stub(:expand, [ item ]) do
      assert_no_difference "Request.count" do
        WatchedSeriesRefreshService.call(watched)
      end
    end

    request.reload
    assert request.pending?
    assert_equal 0, request.retry_count
    assert_not request.attention_needed?
  end

  test "repairs missing series metadata on an existing watched book" do
    watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "29395",
      title: "The Primal Hunter",
      book_types: [ "audiobook" ]
    )
    book = Book.create!(
      title: "The Primal Hunter",
      author: "Zogarth",
      book_type: :audiobook,
      hardcover_id: "111",
      series: nil,
      series_position: nil
    )
    item = MetadataCollectionService::Item.new(
      work_id: "hardcover:111",
      source_work_ids: [ "hardcover:111" ],
      metadata_attrs: {
        title: "The Primal Hunter",
        author: "Zogarth",
        series: "The Primal Hunter",
        series_position: "1"
      }
    )

    SettingsService.set(:library_platform, "audiobookshelf")
    SettingsService.set(:audiobookshelf_url, "http://localhost:13378")
    SettingsService.set(:audiobookshelf_api_key, "test-api-key")
    book.update!(file_path: "/audiobooks/Zogarth/The Primal Hunter (2022)")

    MetadataCollectionService.stub(:expand, [ item ]) do
      assert_enqueued_with(job: AudiobookshelfMetadataSyncJob, args: [ book.id ]) do
        assert_no_difference "Request.count" do
          WatchedSeriesRefreshService.call(watched)
        end
      end
    end

    book.reload
    assert_equal "The Primal Hunter", book.series
    assert_equal "1", book.series_position
  end

  test "clears legacy attention noise for monitored Hardcover series requests" do
    watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "29395",
      title: "The Primal Hunter",
      book_types: [ "audiobook" ]
    )
    book = Book.create!(
      title: "The Primal Hunter 17",
      author: "Zogarth",
      book_type: :audiobook,
      hardcover_id: "777",
      series: "The Primal Hunter",
      series_position: "17"
    )
    request = Request.create!(
      user: @user,
      book: book,
      status: :searching,
      attention_needed: true,
      issue_description: "Search results found but none matched auto-select criteria. Please review and select a result manually.",
      collection_source: "hardcover",
      collection_id: "29395",
      collection_title: "The Primal Hunter"
    )
    item = MetadataCollectionService::Item.new(
      work_id: "hardcover:777",
      source_work_ids: [ "hardcover:777" ],
      metadata_attrs: {
        title: "The Primal Hunter 17",
        author: "Zogarth",
        series: "The Primal Hunter",
        series_position: "17"
      }
    )

    MetadataCollectionService.stub(:expand, [ item ]) do
      WatchedSeriesRefreshService.call(watched)
    end

    request.reload
    assert request.not_found?
    assert_not request.attention_needed?
    assert_nil request.issue_description
    assert request.next_retry_at.present?
  end

  test "does not delay a fresh pending monitored request" do
    watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "29395",
      title: "The Primal Hunter",
      book_types: [ "audiobook" ]
    )
    book = Book.create!(
      title: "The Primal Hunter 18",
      author: "Zogarth",
      book_type: :audiobook,
      hardcover_id: "778",
      series: "The Primal Hunter",
      series_position: "18"
    )
    request = Request.create!(
      user: @user,
      book: book,
      status: :pending,
      collection_source: "hardcover",
      collection_id: "29395",
      collection_title: "The Primal Hunter"
    )
    item = MetadataCollectionService::Item.new(
      work_id: "hardcover:778",
      source_work_ids: [ "hardcover:778" ],
      metadata_attrs: {
        title: "The Primal Hunter 18",
        author: "Zogarth",
        series: "The Primal Hunter",
        series_position: "18"
      }
    )

    MetadataCollectionService.stub(:expand, [ item ]) do
      WatchedSeriesRefreshService.call(watched)
    end

    request.reload
    assert request.pending?
    assert_nil request.next_retry_at
    assert_not request.attention_needed?
  end

  test "does not re-request a previously known failed series book" do
    watched = WatchedSeries.create!(
      user: @user,
      collection_source: "hardcover",
      collection_id: "987",
      title: "Test Series",
      book_types: [ "audiobook" ]
    )
    book = Book.create!(
      title: "Known Book",
      book_type: :audiobook,
      hardcover_id: "333"
    )
    Request.create!(user: @user, book: book, status: :failed)

    item = MetadataCollectionService::Item.new(
      work_id: "hardcover:333",
      source_work_ids: [ "hardcover:333" ],
      metadata_attrs: {
        title: "Known Book",
        series: "Test Series",
        series_position: "2"
      }
    )

    MetadataCollectionService.stub(:expand, [ item ]) do
      assert_no_difference "Request.count" do
        result = WatchedSeriesRefreshService.call(watched)
        assert_equal 1, result.skipped_items
      end
    end
  end
end
