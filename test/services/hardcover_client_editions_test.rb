# frozen_string_literal: true

require "test_helper"

class HardcoverClientEditionsTest < ActiveSupport::TestCase
  setup do
    @original_token = SettingsService.get(:hardcover_api_token)
    @original_enabled = SettingsService.get(:hardcover_enabled, default: true)
    @original_cache = Rails.cache

    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    SettingsService.set(:hardcover_enabled, true)
    SettingsService.set(:hardcover_api_token, "test_token")

    HardcoverClient.reset_connection!
    HardcoverClient.reset_rate_limit_state!
  end

  teardown do
    HardcoverClient.reset_rate_limit_state!
    HardcoverClient.reset_connection!

    SettingsService.set(:hardcover_api_token, @original_token || "")
    SettingsService.set(:hardcover_enabled, @original_enabled)

    Rails.cache = @original_cache
  end

  test "book_editions parses audiobook identifiers" do
    VCR.turned_off do
      stub_request(:post, HardcoverClient::BASE_URL)
        .with do |request|
          body = JSON.parse(request.body)

          body["query"].include?("GetBookEditions") &&
            body.dig("variables", "bookId") == 995246
        end
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: {
            data: {
              editions: [
                {
                  id: 31_991_971,
                  title: "The Primal Hunter 3",
                  asin: "B0B6JRLWVY",
                  audio_seconds: 66_180,
                  edition_format: "Audiobook",
                  reading_format_id: 2,
                  isbn_10: nil,
                  isbn_10_valid: nil,
                  isbn_13: nil,
                  isbn_13_valid: nil,
                  isbns_match: nil,
                  release_date: "2022-08-30",
                  release_year: 2022
                }
              ]
            }
          }.to_json
        )

      editions = HardcoverClient.book_editions("995246")

      assert_equal 1, editions.size

      edition = editions.first

      assert_kind_of HardcoverClient::EditionDetails, edition
      assert_equal 31_991_971, edition.id
      assert_equal "Audiobook", edition.edition_format
      assert_equal 66_180, edition.audio_seconds
      assert_equal "B0B6JRLWVY", edition.asin
      assert_equal 2, edition.reading_format_id
    end
  end
end
