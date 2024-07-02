#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'open3'
require 'time'

class AWSABUtilities
  def validate_and_convert_to_epoch(input)
    begin
      if input.is_a?(Integer)
        epoch_time = input
      else
        datetime = Time.parse(input)
        epoch_time = datetime.to_i
      end
    rescue ArgumentError
      raise "Invalid datetime format"
    end
    epoch_time
  end
end

class AWSCLIRunner
  def initialize(profile)
    @profile = profile
    @aws_installed = check_aws_installed
    raise "AWS CLI is not installed" unless @aws_installed
    @logged_in = check_login
    raise "Not logged in to AWS with the provided profile" unless @logged_in
  end

  def check_aws_installed
    stdout, stderr, status = Open3.capture3('aws --version')
    status.success?
  end

  def check_login
    command = @profile ? "aws sts get-caller-identity --profile #{@profile}" : "aws sts get-caller-identity"
    stdout, stderr, status = Open3.capture3(command)
    status.success? && stderr.empty? && !stdout.empty?
  end

  def query_cloudwatch_logs(log_group, start_time, end_time, filter_pattern)
    start_time = AWSABUtilities::validate_and_convert_to_epoch(start_time)
    end_time = AWSABUtilities::validate_and_convert_to_epoch(end_time)
    command = [
      "aws logs filter-log-events",
      "--log-group-name #{log_group}",
      "--start-time #{start_time}",
      "--end-time #{end_time}",
      "--filter-pattern '#{filter_pattern}'"
    ]
    command << "--profile #{@profile}" if @profile

    stdout, stderr, status = Open3.capture3(command.join(' '))
    status.success? ? JSON.parse(stdout) : "Error querying CloudWatch logs: #{stderr}"
  end
end

class AWSAbstractor
  SERVICES = {
    cloudwatch_logs: {
      description: "Query CloudWatch logs",
      params: [
        { key: :log_group, prompt: "Enter CloudWatch log group name: " },
        { key: :start_time, prompt: "Enter start datetime: " },
        { key: :end_time, prompt: "Enter end datetime: " },
        { key: :filter_pattern, prompt: "Enter filter pattern for CloudWatch logs: " }
      ]
    },
  }

  def initialize
    @options = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: my_utility [options]"

      opts.on("-pPROFILE", "--profile=PROFILE", "AWS profile to use") do |profile|
        @options[:profile] = profile
      end

      SERVICES.each do |service, config|
        opts.on("--#{service}", config[:description]) do
          @options[:service] = service
        end
      end

      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end.parse!

    @aws_checker = AWSCLIRunner.new(@options[:profile])
  end

  def prompt_for_missing_options
    service_config = SERVICES[@options[:service]]
    service_config[:params].each do |param|
      unless @options[param[:key]]
        print param[:prompt]
        input = gets.chomp
        @options[param[:key]] = param[:type] == :integer ? input.to_i : input
      end
    end
  end

  def run
    unless @options[:service]
      puts "No action specified. Use -h for help."
      exit 1
    end

    prompt_for_missing_options

    if @options[:service] == :cloudwatch_logs
      result = @aws_checker.query_cloudwatch_logs(
        @options[:log_group],
        @options[:start_time],
        @options[:end_time],
        @options[:filter_pattern]
      )

      if result.is_a?(String)
        puts result
      else
        puts "CloudWatch Log Events:"
        puts JSON.pretty_generate(result)
      end
    end

    # Add more service handlers here
  end
end

AWSAbstractor.new.run
