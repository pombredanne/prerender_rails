module Rack
  class Prerender
    require 'net/http'

    def initialize(app, options={})
      # googlebot, yahoo, and bingbot are in this list even though
      # we support _escaped_fragment_ to ensure it works for people
      # who might not use the _escaped_fragment_ protocol
      @crawler_user_agents = [
        'googlebot',
        'yahoo',
        'bingbot',
        'baiduspider',
        'facebookexternalhit',
        'twitterbot'
      ]

      @extensions_to_ignore = [
        '.js',
        '.css',
        '.xml',
        '.less',
        '.png',
        '.jpg',
        '.jpeg',
        '.gif',
        '.pdf',
        '.doc',
        '.txt',
        '.zip',
        '.mp3',
        '.rar',
        '.exe',
        '.wmv',
        '.doc',
        '.avi',
        '.ppt',
        '.mpg',
        '.mpeg',
        '.tif',
        '.wav',
        '.mov',
        '.psd',
        '.ai',
        '.xls',
        '.mp4',
        '.m4a',
        '.swf',
        '.dat',
        '.dmg',
        '.iso',
        '.flv',
        '.m4v',
        '.torrent'
      ]

      @options = options
      @options[:whitelist] = [@options[:whitelist]] if @options[:whitelist].is_a? String
      @options[:blacklist] = [@options[:blacklist]] if @options[:blacklist].is_a? String
      @app = app
    end

    def call(env)

      if should_show_prerendered_page(env)
        prerendered_response = get_prerendered_page_response(env)

        if prerendered_response
          response = Rack::Response.new(prerendered_response.body, prerendered_response.code, prerendered_response.header)
          return response.finish
        end
      end

      @app.call(env)  
    end

    def should_show_prerendered_page(env)
      user_agent = env['HTTP_USER_AGENT']
      return false if !user_agent
      return false if env['REQUEST_METHOD'] != 'GET'

      request = Rack::Request.new(env)

      return true if Rack::Utils.parse_query(request.query_string).has_key?('_escaped_fragment_')

      #if it is not a bot...dont prerender
      return false if @crawler_user_agents.all? { |crawler_user_agent| !user_agent.downcase.include?(crawler_user_agent.downcase) }

      #if it is a bot and is requesting a resource...dont prerender
      return false if @extensions_to_ignore.any? { |extension| request.path.include? extension }

      #if it is a bot and not requesting a resource and is not whitelisted...dont prerender
      return false if @options[:whitelist].is_a?(Array) && @options[:whitelist].all? { |whitelisted| !Regexp.new(whitelisted).match(request.path) }

      #if it is a bot and not requesting a resource and is not blacklisted(url or referer)...dont prerender
      if @options[:blacklist].is_a?(Array) && @options[:blacklist].any? { |blacklisted|
          blacklistedUrl = false
          blacklistedReferer = false
          regex = Regexp.new(blacklisted)

          blacklistedUrl = !!regex.match(request.path)
          blacklistedReferer = !!regex.match(request.referer) if request.referer

          blacklistedUrl || blacklistedReferer
        }
        return false
      end 

      return true
    end

    def get_prerendered_page_response(env)
      begin
        url = URI.parse(build_api_url(env))
        headers = { 'User-Agent' => env['HTTP_USER_AGENT'] }
        headers['X-Prerender-Token'] = ENV['PRERENDER_TOKEN'] if ENV['PRERENDER_TOKEN']
        req = Net::HTTP::Get.new(url.request_uri, headers)
        response = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
      rescue
        nil
      end
    end

    def build_api_url(env)
      new_env = env
      if env["CF-VISITOR"]
        match = /"scheme":"(http|https)"/.match(env['CF-VISITOR'])
        new_env["HTTPS"] = true and new_env["rack.url_scheme"] = "https" and new_env["SERVER_PORT"] = 443 if (match && match[1] == "https")
        new_env["HTTPS"] = false and new_env["rack.url_scheme"] = "http" and new_env["SERVER_PORT"] = 80 if (match && match[1] == "http")
      end

      url = Rack::Request.new(new_env).url
      prerender_url = get_prerender_service_url()
      forward_slash = prerender_url[-1, 1] == '/' ? '' : '/'
      "#{prerender_url}#{forward_slash}#{url}"
    end

    def get_prerender_service_url
      @options[:prerender_service_url] || ENV['PRERENDER_SERVICE_URL'] || 'http://prerender.herokuapp.com/'
    end
  end
end
