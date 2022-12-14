# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "stud/buffer"
require "logstash/logAnalyticsClient/logStashAutoResizeBuffer"
require "logstash/logAnalyticsClient/logstashLoganalyticsConfiguration"

class LogStash::Outputs::AzureLogAnalytics < LogStash::Outputs::Base

  config_name "sentinelblue-logstash-output-azure-loganalytics"
  
  # Stating that the output plugin will run in concurrent mode
  concurrency :shared

  # Your Operations Management Suite workspace ID
  config :workspace_id, :validate => :string, :required => true

  # The primary or the secondary key used for authentication, required by Azure Loganalytics REST API
  config :workspace_key, :validate => :string, :required => true

  # The name of the event type that is being submitted to Log Analytics. 
  # This must be only alpha characters, numbers and underscore.
  # This must not exceed 100 characters.
  # Table name under custom logs in which the data will be inserted
  config :custom_log_table_name, :validate => :string, :required => true

  # The service endpoint (Default: ods.opinsights.azure.com)
  config :endpoint, :validate => :string, :default => 'ods.opinsights.azure.com'

  # The name of the time generated field.
  # Be careful that the value of field should strictly follow the ISO 8601 format (YYYY-MM-DDThh:mm:ssZ)
  config :time_generated_field, :validate => :string, :default => ''

  # Subset of keys to send to the Azure Loganalytics workspace
  config :key_names, :validate => :array, :default => []

  # # Max number of items to buffer before flushing. Default 50.
  # config :flush_items, :validate => :number, :default => 50
  
  # Max number of seconds to wait between flushes. Default 5
  config :plugin_flush_interval, :validate => :number, :default => 5

  # Factor for adding to the amount of messages sent
  config :decrease_factor, :validate => :number, :default => 100

  # This will trigger message amount resizing in a REST request to LA
  config :amount_resizing, :validate => :boolean, :default => true

  # Setting the default amount of messages sent                                                                                                    
  # it this is set with amount_resizing=false --> each message will have max_items
  config :max_items, :validate => :number, :default => 2000

  # Setting proxy to be used for the Azure Loganalytics REST client
  config :proxy, :validate => :string, :default => ''

  # This will set the amount of time given for retransmitting messages once sending is failed
  config :retransmission_time, :validate => :number, :default => 10

  # Optional to override the resource ID field on the workspace table.
  # Resource ID provided must be a valid resource ID on azure 
  config :azure_resource_id, :validate => :string, :default => ''

  public
  def register
    @logstash_configuration= build_logstash_configuration()
    # Validate configuration correctness 
    @logstash_configuration.validate_configuration()
    @logger.info("Logstash Sentinel Blue Azure Log Analytics output plugin configuration was found valid")

    # Initialize the logstash resizable buffer
    # This buffer will increase and decrease size according to the amount of messages inserted.
    # If the buffer reached the max amount of messages the amount will be increased until the limit
    # @logstash_resizable_event_buffer=LogStashAutoResizeBuffer::new(@logstash_configuration)

  end # def register

  def multi_receive(events)

    # Create a hash table for each buffer. A buffer is needed per table used
    buffers = Hash.new

    events.each do |event|
      # creating document from event
      document = create_event_document(event)
      # Skip if document doesn't contain any items  
      next if (document.keys).length < 1

      # Get the custom table name 
      custom_table_name = ""

      # Check if the table name is static or dynamic
      if @custom_log_table_name.match(/^[[:alpha:][:digit:]_]+$/)
        # Table name is static.
        custom_table_name = @custom_log_table_name

      # /^%\{((([a-zA-Z]|[0-9]|_)+)|(\[((([a-zA-Z]|[0-9]|_|@)+))\])+)\}$/
      elsif @custom_log_table_name.match(/^%{((\[[\w_\-@]*\])*)([\w_\-@]*)}$/)
        # Table name is dynamic
        custom_table_name = event.sprintf(@custom_log_table_name)

      else
        # Incorrect format
        @logger.warn("custom_log_table_name must be either a static name consisting only of numbers, letters, and underscores OR a dynamic table name of the format used by logstash (e.g. %{field_name}, %{[nested][field]}.")
        break

      end

      # Check that the table name is a string, exists, and is les than 100 characters
      if !custom_table_name.is_a?(String)
        @logger.warn("The custom table name must be a string. If you used a dynamic name from one of the log fields, make sure it is a string.")
        break
        
      elsif custom_table_name.empty? or custom_table_name.nil?
        @logger.warn("The custom table name is empty. If you used a dynamic name from one of the log fields, check that it exists.")
        break

      elsif custom_table_name.length > 100
        @logger.warn("The custom table name must not exceed 100 characters")
        break

      end

      @logger.info("Custom table name #{custom_table_name} is valid")

      # Determine if there is a buffer for the given table
      if buffers.keys.include?(custom_table_name)
        @logger.trace("Adding event document - " + event.to_s)
        buffers[custom_table_name].add_event_document(document)
    
      else
        # If the buffer doesn't exist for the table, create one and add the document
        buffers[custom_table_name] = LogStashAutoResizeBuffer::new(@logstash_configuration,custom_table_name)
        @logger.trace("Adding event document - " + event.to_s)
        buffers[custom_table_name].add_event_document(document)

      end
        
    end # events.each do
  end # def multi_receive
  
  #private 
  private

  # In case that the user has defined key_names meaning that he would like to a subset of the data,
  # we would like to insert only those keys.
  # If no keys were defined we will send all the data 
   
  def create_event_document(event)
    document = {}
    event_hash = event.to_hash()
    if @key_names.length > 0
      # Get the intersection of key_names and keys of event_hash
      keys_intersection = @key_names & event_hash.keys
      keys_intersection.each do |key|
        document[key] = event_hash[key]
      end
      if document.keys.length < 1
        @logger.warn("No keys found, message is dropped. Plugin keys: #{@key_names}, Event keys: #{event_hash}. The event message do not match event expected structre. Please edit key_names section in output plugin and try again.")
      end
    else
      document = event_hash
    end

    return document
  end # def create_event_document

  # Building the logstash object configuration from the output configuration provided by the user
  # Return LogstashLoganalyticsOutputConfiguration populated with the configuration values
  def build_logstash_configuration()
    logstash_configuration= LogstashLoganalyticsOutputConfiguration::new(@workspace_id, @workspace_key, @logger)    
    logstash_configuration.endpoint = @endpoint
    logstash_configuration.time_generated_field = @time_generated_field
    logstash_configuration.key_names = @key_names
    logstash_configuration.plugin_flush_interval = @plugin_flush_interval
    logstash_configuration.decrease_factor = @decrease_factor
    logstash_configuration.amount_resizing = @amount_resizing
    logstash_configuration.max_items = @max_items
    logstash_configuration.azure_resource_id = @azure_resource_id
    logstash_configuration.proxy = @proxy
    logstash_configuration.retransmission_time = @retransmission_time
    
    return logstash_configuration
  end # def build_logstash_configuration

end # class LogStash::Outputs::AzureLogAnalytics
