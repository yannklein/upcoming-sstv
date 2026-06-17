# myapp.rb
require 'sinatra'
require 'ruby_llm'
require 'open-uri'
require "nokogiri"
require 'dotenv/load' if ENV['RACK_ENV'] == 'development'

# Configure RubyLLM with your API key
CACHE_TTL = 3600
$cache = { data: nil, fetched_at: nil }

RubyLLM.configure do |config|
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  config.default_model = 'claude-sonnet-4-6' 
end

# Define a simple route to handle AI requests
get '/' do
  if $cache[:data] && Time.now - $cache[:fetched_at] < CACHE_TTL
    content_type :json
    next $cache[:data]
  end

  ariss_url = 'https://www.ariss.org/upcoming-sstv-events.html'

  html_file = begin
    URI.parse(ariss_url).read
  rescue OpenURI::HTTPError, SocketError, Timeout::Error => e
    halt 502, content_type(:json) && { error: "Failed to fetch ARISS data: #{e.message}" }.to_json
  end
  html_doc = Nokogiri::HTML.parse(html_file)

  ariss_events_text =  html_doc.search("h2 + div.paragraph").text.strip

  prompt = <<~PROMPT
    You are a JSON API that extracts ISS SSTV event data from the ARISS website.

    Output ONLY a valid JSON array. No explanation, no markdown, no code fences — raw JSON only.

    Each event object must have exactly these fields:
    - "name": string — full event name
    - "publication_date": string — publication date in YYYY-MM-DD format
    - "startUTC": string — event start in ISO 8601 format (e.g. "2026-05-08T10:30:00Z")
    - "endUTC": string — event end in ISO 8601 format (e.g. "2026-05-12T16:40:00Z")
    - "frequency": number in Hz (e.g. 437550000), or null if not provided
    - "description": string or null

    Rules:
    - Omit any event that is missing a start or end time
    - "frequency" must be a number, not a string
    - Output must be valid, parseable JSON with double-quoted keys and string values

    Example output for a single event:
    [
      {
        "name": "SSTV Expedition 74 Series 32 features \"Cooperation in Space\"",
        "publication_date": "2026-05-06",
        "startUTC": "2026-05-08T10:30:00Z",
        "endUTC": "2026-05-12T16:40:00Z",
        "frequency": 437550000,
        "description": null
      }
    ]

    ARISS website content:
    #{ariss_events_text}
  PROMPT

  chat = RubyLLM.chat
  
  # Send a prompt and get the response
  response = chat.ask prompt

  content_type :json
  begin
    JSON.parse(response.content)
    $cache[:data] = response.content
    $cache[:fetched_at] = Time.now
    response.content
  rescue JSON::ParserError
    halt 500, { error: 'LLM returned invalid JSON' }.to_json
  end
end