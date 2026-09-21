# frozen_string_literal: true

module DownloadClients
  class Decypharr < Qbittorrent
    private

    def session_cookie_pattern
      /\b(?<name>SID|sid)=(?<value>[^;]+)/i
    end

    def default_session_cookie_name
      "sid"
    end

    # Decypharr's qBittorrent compatibility API authenticates with its SID cookie.
    def api_key
      nil
    end

    def adapter_specific_add_torrent_params
      provider = SettingsService.get(:decypharr_debrid_provider, default: "").to_s.strip
      provider.present? ? { debrid: provider } : {}
    end
  end
end
