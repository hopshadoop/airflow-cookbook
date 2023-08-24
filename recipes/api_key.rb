# Generate an API key
api_key = nil
ruby_block 'generate-api-key' do
  block do
    require 'net/https'
    require 'http-cookie'
    require 'json'
    require 'securerandom'

    hopsworks_fqdn = consul_helper.get_service_fqdn("hopsworks.glassfish")
    _, hopsworks_port = consul_helper.get_service("glassfish", ["http", "hopsworks"])
    if hopsworks_port.nil? || hopsworks_fqdn.nil?
      raise "Could not get Hopsworks fqdn/port from local Consul agent. Verify Hopsworks is running with service name: glassfish and tags: [http, hopsworks]"
    end

    hopsworks_endpoint = "https://#{hopsworks_fqdn}:#{hopsworks_port}"
    url = URI.parse("#{hopsworks_endpoint}/hopsworks-api/api/auth/service")
    api_key_url = URI.parse("#{hopsworks_endpoint}/hopsworks-api/api/users/apiKey")

    params =  {
      :email => node['airflow']['user']['email'],
      :password => node['airflow']['user']['pwd']
    }

    api_key_params = {
      :name => "airflow_" + SecureRandom.hex(12),
      :scope => "JOB"
    }

    http = Net::HTTP.new(url.host, url.port)
    http.read_timeout = 120
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    jar = ::HTTP::CookieJar.new

    http.start do |connection|

      request = Net::HTTP::Post.new(url)
      request.set_form_data(params, '&')
      response = connection.request(request)

      if( response.is_a?( Net::HTTPSuccess ) )
        # your request was successful
        puts "Airflow login successful: -> #{response.body}"

        response.get_fields('Set-Cookie').each do |value|
          jar.parse(value, url)
        end

        api_key_url.query = URI.encode_www_form(api_key_params)
        request = Net::HTTP::Post.new(api_key_url)
        request['Content-Type'] = "application/json"
        request['Cookie'] = ::HTTP::Cookie.cookie_value(jar.cookies(api_key_url))
        request['Authorization'] = response['Authorization']
        response = connection.request(request)

        if ( response.is_a? (Net::HTTPSuccess))
          json_response = ::JSON.parse(response.body)
          api_key = json_response['key']
        else
          puts response.body
          raise "Error creating airflow api-key: #{response.uri}"
        end
      else
        puts response.body
        raise "Error airflow login"
      end
    end
  end
end

# write api-key to token file
file node['airflow']['api_key_file']  do
  content lazy {api_key}
  mode node['airflow']["config_file_mode"]
  owner node['airflow']['user']
  group node['airflow']['user']
end