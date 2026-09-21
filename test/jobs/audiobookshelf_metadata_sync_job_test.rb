# frozen_string_literal: true

require "test_helper"

class AudiobookshelfMetadataSyncJobTest < ActiveJob::TestCase
  setup do
    SettingsService.set(:library_platform, "audiobookshelf")
    SettingsService.set(:audiobookshelf_url, "http://localhost:13378")
    SettingsService.set(:audiobookshelf_api_key, "test-api-key")
    SettingsService.set(:audiobookshelf_audiobook_library_id, "audio-lib")
    SettingsService.set(:audiobook_output_path, "/audiobooks")

    @book = books(:audiobook_acquired)
    @book.update!(
      title: "The Primal Hunter 3",
      author: "Zogarth",
      series: "The Primal Hunter",
      series_position: "3",
      narrator: "Travis Baldree",
      file_path: "/audiobooks/Zogarth/The Primal Hunter 3"
    )
  end

  test "finds ABS item by relative library path and updates metadata" do
    lookups = []
    updates = []

    finder = lambda do |library_id, relative_path|
      lookups << [ library_id, relative_path ]
      { "id" => "abs-ph3" }
    end

    updater = lambda do |item_id, book|
      updates << [ item_id, book.id ]
      true
    end

    AudiobookshelfClient.stub(:find_item_by_relative_path, finder) do
      AudiobookshelfClient.stub(:update_book_metadata, updater) do
        AudiobookshelfLibrarySyncJob.stub(:schedule_post_scan_refresh!, -> { true }) do
          AudiobookshelfMetadataSyncJob.perform_now(@book.id)
        end
      end
    end

    assert_equal [
      [ "audio-lib", "Zogarth/The Primal Hunter 3" ]
    ], lookups

    assert_equal [
      [ "abs-ph3", @book.id ]
    ], updates
  end

  test "does nothing when book has no library path" do
    @book.update!(file_path: nil)

    called = false

    AudiobookshelfClient.stub(:find_item_by_relative_path, ->(*) {
      called = true
      nil
    }) do
      AudiobookshelfMetadataSyncJob.perform_now(@book.id)
    end

    assert_not called
  end
end
