# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

class SeriesBacklogService
  DEFAULT_DAILY_LIMIT = 10
  STATE_PATH = Rails.root.join("storage", "series_backlog.json")
  LOCK_PATH = Rails.root.join("storage", "series_backlog.lock")

  class Error < StandardError; end

  class << self
    def add(names)
      mutate_state do |state|
        existing = state.fetch("entries").index_by { |entry| normalized_name(entry["name"]) }

        Array(names).each do |name|
          clean_name = name.to_s.strip
          next if clean_name.blank?
          next if existing.key?(normalized_name(clean_name))

          entry = {
            "name" => clean_name,
            "status" => "pending",
            "series_id" => nil,
            "resolved_name" => nil,
            "error" => nil,
            "added_at" => Time.current.iso8601,
            "queued_at" => nil
          }
          state["entries"] << entry
          existing[normalized_name(clean_name)] = entry
        end
      end
    end

    def run(limit: DEFAULT_DAILY_LIMIT)
      limit = Integer(limit)
      raise ArgumentError, "limit must be positive" unless limit.positive?

      mutate_state do |state|
        user = User.active.admin.first || User.active.first
        raise Error, "No active Shelfarr user is available for backlog requests" unless user

        pending = state.fetch("entries").select { |entry| entry["status"] == "pending" }.first(limit)

        pending.each do |entry|
          begin
            series = HardcoverClient.find_series_exact(entry.fetch("name"))

            result = RequestCreationService.call(
              user: user,
              work_id: "hardcover:series-#{series.id}",
              book_types: [ "audiobook" ],
              metadata_attrs: {
                title: series.name,
                content_kind: "book",
                request_scope: "collection",
                collection_source: "hardcover",
                collection_id: series.id,
                collection_title: series.name
              },
              origin: {
                created_via: "api",
                external_source: "series_backlog"
              }
            )

            unless result.success?
              raise Error, result.errors.presence&.join(". ") || "Shelfarr rejected the collection request"
            end

            entry["status"] = "queued"
            entry["series_id"] = series.id
            entry["resolved_name"] = series.name
            entry["error"] = nil
            entry["queued_at"] = Time.current.iso8601
          rescue StandardError => e
            entry["status"] = "error"
            entry["error"] = "#{e.class}: #{e.message}"
          end
        end

        state["last_run_at"] = Time.current.iso8601
        state["last_run_limit"] = limit
      end
    end

    def retry_errors
      mutate_state do |state|
        state.fetch("entries").each do |entry|
          next unless entry["status"] == "error"

          entry["status"] = "pending"
          entry["error"] = nil
        end
      end
    end

    def state
      with_lock { load_state }
    end

    private

    def mutate_state
      with_lock do
        current = load_state
        yield current
        write_state(current)
        current
      end
    end

    def with_lock
      FileUtils.mkdir_p(STATE_PATH.dirname)
      File.open(LOCK_PATH, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock.flock(File::LOCK_UN) rescue nil
      end
    end

    def load_state
      return default_state unless File.exist?(STATE_PATH)

      parsed = JSON.parse(File.read(STATE_PATH))
      parsed["entries"] = Array(parsed["entries"])
      parsed
    rescue JSON::ParserError
      raise Error, "Series backlog state is not valid JSON"
    end

    def write_state(state)
      tmp_path = "#{STATE_PATH}.tmp-#{Process.pid}"
      File.write(tmp_path, JSON.pretty_generate(state))
      File.chmod(0o600, tmp_path)
      File.rename(tmp_path, STATE_PATH)
    ensure
      File.delete(tmp_path) if defined?(tmp_path) && File.exist?(tmp_path)
    end

    def default_state
      {
        "version" => 1,
        "entries" => [],
        "last_run_at" => nil,
        "last_run_limit" => nil
      }
    end

    def normalized_name(name)
      name.to_s.strip.downcase
    end
  end
end
