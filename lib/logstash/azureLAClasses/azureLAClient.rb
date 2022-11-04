# encoding: utf-8
require "logstash/azureLAClasses/logAnalyticsConfiguration"
require 'rest-client'
require 'json'
require 'openssl'
require 'base64'
require 'time'

class AzureLAClient
  API_VERSION = '2016-04-01'.freeze

  def initialize (logAnalyticsConfiguration)
    @logAnalyticsConfiguration = logAnalyticsConfiguration
    set_proxy(@logAnalyticsConfiguration.proxy)
    @uri = sprintf("https://%s.%s/api/logs?api-version=%s", @logAnalyticsConfiguration.workspace_id, @logAnalyticsConfiguration.endpoint, API_VERSION)
  end # def initialize


  # Post the given json to Azure Loganalytics
  def post_data(body,custom_table_name)
    raise ConfigError, 'no json_records' if body.empty?
    # Create REST request header
    header = get_header(body.bytesize,custom_table_name)
    # Post REST request 
    response = RestClient.post(@uri, body, header)

    return response
  end # def post_data

  private 

  # Create a header for the given length 
  def get_header(body_bytesize_length,custom_table_name)
    # We would like each request to be sent with the current time
    date = rfc1123date()

    return {
      'Content-Type' => 'application/json',
      'Authorization' => signature(date, body_bytesize_length),
      'Log-Type' => custom_table_name,
      'x-ms-date' => date,
      'time-generated-field' =>  @logAnalyticsConfiguration.time_generated_field,
      'x-ms-AzureResourceId' => @logAnalyticsConfiguration.azure_resource_id
    }
  end # def get_header

  # Setting proxy for the REST client.
  # This option is not used in the output plugin and will be used 
  #  
  def set_proxy(proxy='')
    RestClient.proxy = proxy.empty? ? ENV['http_proxy'] : proxy
  end # def set_proxy

  # Return the current data 
  def rfc1123date()
    current_time = Time.now
    
    return current_time.httpdate()
  end # def rfc1123date

  def signature(date, body_bytesize_length)
    sigs = sprintf("POST\n%d\napplication/json\nx-ms-date:%s\n/api/logs", body_bytesize_length, date)
    utf8_sigs = sigs.encode('utf-8')
    decoded_shared_key = Base64.decode64(@logAnalyticsConfiguration.workspace_key)
    hmac_sha256_sigs = OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha256'), decoded_shared_key, utf8_sigs)
    encoded_hash = Base64.encode64(hmac_sha256_sigs)
    authorization = sprintf("SharedKey %s:%s", @logAnalyticsConfiguration.workspace_id, encoded_hash)
    
    return authorization
  end # def signature

end # end of class