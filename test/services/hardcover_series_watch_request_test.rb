# frozen_string_literal: true

require "test_helper"

class HardcoverSeriesWatchRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    SettingsService.set(:hardcover_series_watch_enabled, true)
    clear_enqueued_jobs
  end

  test "requesting a Hardcover collection automatically watches that exact series" do
    HardcoverClient.stub(:configured?, true) do
      assert_difference "WatchedSeries.count", 1 do
        assert_enqueued_with(job: CollectionRequestExpansionJob) do
          result = RequestCreationService.call(
            user: @user,
            work_id: "hardcover:series-987",
            book_types: [ "audiobook" ],
            metadata_attrs: {
              title: "Test Series",
              content_kind: "book",
              request_scope: "collection",
              collection_source: "hardcover",
              collection_id: "987",
              collection_title: "Test Series"
            }
          )

          assert result.queued?
        end
      end
    end

    watched = WatchedSeries.last
    assert_equal "987", watched.collection_id
    assert_equal "Test Series", watched.title
    assert_equal [ "audiobook" ], watched.normalized_book_types
  end
end
