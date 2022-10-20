# Sentinel Blue Azure Log Analytics output plugin for Logstash

Sentinel Blue provides an updated output plugin for Logstash. Using this output plugin, you will be able to send any log you want using Logstash to the Azure Sentinel/Log Analytics workspace using dynamic custom table names.

This allows you to set your destination table in your filtering process and reference it in the output plugin. The original plugin functionality has been preserved as well.

Azure Sentinel output plugin uses the rest API integration to Log Analytics, in order to ingest the logs into custom logs tables [What are custom logs tables](<https://docs.microsoft.com/azure/azure-monitor/platform/data-sources-custom-logs>)

This plugin is based on the original provided by the Azure Sentinel team. View the original plugin here: <https://github.com/Azure/Azure-Sentinel/tree/master/DataConnectors/microsoft-logstash-output-azure-loganalytics>

```text
Plugin version: v1.1.1
Released on: 2022-10-20
```

This plugin is currently in development and is free to use. We welcome contributions from the open source community on this project, and we request and appreciate feedback from users.

<https://rubygems.org/gems/sentinelblue-logstash-output-azure-loganalytics>

## Support

For issues regarding the output plugin please open a support issue here. Create a new issue describing the problem so that we can assist you.

## Installation

Install the sentinelblue-logstash-output-azure-loganalytics, use [Logstash Working with plugins](<https://www.elastic.co/guide/en/logstash/current/working-with-plugins.html>) document.
For offline setup follow [Logstash Offline Plugin Management instruction](<https://www.elastic.co/guide/en/logstash/current/offline-plugins.html>).

```bash
logstash-plugin install sentinelblue-logstash-output-azure-loganalytics
```

Required Logstash version: between 7.0+

## Configuration

in your Logstash configuration file, add the Azure Sentinel output plugin to the configuration with following values:

- workspace_id
  - your workspace ID guid
- workspace_key (primary key)
  - your workspace primary key guid. You can find your workspace key and id the following path: Home > Log Analytics workspace > Advanced settings
- custom_log_table_name
  - table name, in which the logs will be ingested, limited to one table, the log table will be presented in the logs blade under the custom logs label, with a _CL suffix.
  - custom_log_table_name must be either a static name consisting only of numbers, letters, and underscores OR a dynamic table name of the format used by logstash (e.g. ```%{field_name}```, ```%{[nested][field]}```.
- endpoint
  - Optional field by default set as log analytics endpoint.  
- time_generated_field
  - Optional field, this property is used to override the default TimeGenerated field in Log Analytics. Populate this property with the name of the sent data time field.
- key_names
  - list of Log analytics output schema fields.
- plugin_flash_interval
  - Optional filed, define the maximal time difference (in seconds) between sending two messages to Log Analytics.
- Max_items
  - Optional field, 2000 by default. this parameter will control the maximum batch size. This value will be changed if the user didn’t specify “amount_resizing = false” in the configuration.

Note: View the GitHub to learn more about the sent message’s configuration, performance settings and mechanism

Security notice: We recommend not to implicitly state the workspace_id and workspace_key in your Logstash configuration for security reasons.
                 It is best to store this sensitive information in a Logstash KeyStore as described here- https://www.elastic.co/guide/en/elasticsearch/reference/current/get-started-logstash-user.html

## Tests

Here is an example configuration who parse Syslog incoming data into a custom table named "logstashCustomTableName".

### Example Configurations

#### Basic configuration

- Using filebeat input pipe

```text
input {
    beats {
        port => "5044"
    }
}
 filter {
}
output {
    sentinelblue-logstash-output-azure-loganalytics {
      workspace_id => "4g5tad2b-a4u4-147v-a4r7-23148a5f2c21" # <your workspace id>
      workspace_key => "u/saRtY0JGHJ4Ce93g5WQ3Lk50ZnZ8ugfd74nk78RPLPP/KgfnjU5478Ndh64sNfdrsMni975HJP6lp==" # <your workspace key>
      custom_log_table_name => "tableName"
    }
}
```

Or using the tcp input pipe

```text
input {
    tcp {
        port => "514"
        type => syslog #optional, will effect log type in table
    }
}
 filter {
}
output {
    sentinelblue-logstash-output-azure-loganalytics {
      workspace_id => "4g5tad2b-a4u4-147v-a4r7-23148a5f2c21" # <your workspace id>
      workspace_key => "u/saRtY0JGHJ4Ce93g5WQ3Lk50ZnZ8ugfd74nk78RPLPP/KgfnjU5478Ndh64sNfdrsMni975HJP6lp==" # <your workspace key>
      custom_log_table_name => "tableName"
    }
}
```

#### Advanced Configuration

```text
input {
  tcp {
    port => 514
    type => syslog
  }
}

filter {
    grok {
      match => { "message" => "<%{NUMBER:PRI}>1 (?<TIME_TAG>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}T[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2})[^ ]* (?<HOSTNAME>[^ ]*) %{GREEDYDATA:MSG}" }
    }
}

output {
        sentinelblue-logstash-output-azure-loganalytics {
                workspace_id => "<WS_ID>"
                workspace_key => "${WS_KEY}"
                custom_log_table_name => "logstashCustomTableName"
                key_names => ['PRI','TIME_TAG','HOSTNAME','MSG']
                plugin_flush_interval => 5
        }
}
```

```text
filter {
    grok {
      match => { "message" => "<%{NUMBER:PRI}>1 (?<TIME_TAG>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}T[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2})[^ ]* (?<HOSTNAME>[^ ]*) %{GREEDYDATA:MSG}" }
    }
}

output {
        sentinelblue-logstash-output-azure-loganalytics {
                workspace_id => "<WS_ID>"
                workspace_key => "${WS_KEY}"
                custom_log_table_name => "%{[event][name]}"
                key_names => ['PRI','TIME_TAG','HOSTNAME','MSG']
                plugin_flush_interval => 5
        }
}
```

Now you are able to run logstash with the example configuration and send mock data using the 'logger' command.

For example:

```text
logger -p local4.warn -t CEF: "0|Microsoft|Device|cef-test|example|data|1|here is some more data for the example" -P 514 -d -n 127.0.0.1
```

Note: this format of pushing logs is not tested. You can tail a file for similar results.

```text
logger -p local4.warn -t JSON: "{"event":{"name":"logstashCustomTableName"},"purpose":"testplugin"}"
```

Alternativly you can use netcat to test your configuration:

```text
echo "test string" | netcat localhost 514
```
