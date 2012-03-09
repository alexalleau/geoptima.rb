#!/usr/bin/env ruby

# useful if being run inside a source code checkout
$: << 'lib'
$: << '../lib'

require 'date'
require 'geoptima'

Geoptima::assert_version("0.0.4")

$debug=false

$event_names=[]
$files = []
$print_limit = 10000

def cw(val)
  val.nil? ? '' : "(#{val})"
end

while arg=ARGV.shift do
  if arg =~ /^\-(\w+)/
    $1.split(//).each do |aa|
      case aa
      when 'h'
        $help=true
      when 'd'
        $debug=true
      when 'p'
        $print=true
      when 'v'
        $verbose=true
      when 'x'
        $export=true
      when 's'
        $seperate=true
      when 'o'
        $export_stats=true
      when 'm'
        $map_headers=true
      when 'E'
        $event_names += ARGV.shift.split(/[\,\;\:\.]+/)
      when 'T'
        $time_range = Range.new(*(ARGV.shift.split(/[\,]+/).map do |t|
          DateTime.parse t
        end))
      when 'L'
        $print_limit = ARGV.shift.to_i
        $print_limit = 10 if($print_limit<1)
      else
        puts "Unrecognized option: -#{aa}"
      end
    end
  else
    if File.exist? arg
      $files << arg
    else
      puts "No such file: #{arg}"
    end
  end
end

$help = true if($files.length < 1)
if $help
  puts <<EOHELP
Usage: ./showGeoptimaEvents.rb <-dvxEh> <-L limit> <-E types> <-T min,max> file <files>
  -d  debug mode (output more context during processing) #{cw $debug}
  -p  print mode (print out final results to console) #{cw $print}
  -v  verbose mode (output extra information to console) #{cw $verbose}
  -x  export IMEI specific CSV files for further processing #{cw $export}
  -o  export field statistis #{cw $export_stats}
  -m  map headers to classic NetView compatible version #{cw $map_headers}
  -s  seperate the export files by event type #{cw $seperate}
  -h  show this help
  -L  limit verbose output to specific number of lines #{cw $print_limit}
  -E  comma-seperated list of event types to show and export (default: all; current: #{$event_names.join(',')})
  -T  time range to limit results to (default: all; current: #{$time_range})
EOHELP
  exit 0
end

$verbose = $verbose || $debug
$datasets = Geoptima::Dataset.make_datasets($files, :locate => true, :time_range => $time_range)

class Export
  attr_reader :files, :imei, :names, :headers
  def initialize(imei,names,dataset)
    @imei = imei
    @names = names
    if $export
      if $seperate
        @files = names.inject({}) do |a,name|
          a[name] = File.open("#{imei}_#{name}.csv",'w')
          a
        end
      else
        @files={nil => File.open("#{imei}.csv",'w')}
      end
    end
    @headers = names.inject({}) do |a,name|
      a[name] = dataset.header([name]).reject{|h| h === 'timeoffset'}
      a[name] = a[name].map{|h| "#{name}.#{h}"} unless($separate)
      puts "Created header for name #{name}: #{a[name].join(',')}" if($debug)
      a
    end
    @headers[nil] = @headers.values.flatten
    files && files.each do |key,file|
      file.puts map_headers(['Time','Event','Latitude','Longitude','IMSI','IMEI']+header(key)).join("\t")
    end
    if $debug || $verbose
      @headers.each do |name,head|
        puts "Header[#{name}]: #{head.join(',')}"
      end
    end
  end
  def cap(array,sep="")
    array.map do |v|
      "#{v[0..0].upcase}#{v[1..-1]}"
    end.join(sep)
  end
  def map_headers(hnames)
    $map_headers && hnames.map do |h|
        case h
        when 'Time'
          'time'
        when /gps\./
          cap(h.split(/[\._]/),'_').gsub(/gps/i,'GPS')
        when /^(call|signal|data|sms|mms|browser|neighbor)/i
          cap(h.split(/[\._]/),'_').gsub(/Neighbor/,'Neighbour').gsub(/mms/i,'MMS').gsub(/sms/,'SMS')
        when /\./
          cap(h.split(/[\._]/))
        else
          h
        end
    end || hnames
  end
  def export_stats(stats)
    File.open("#{imei}_stats.csv",'w') do |out|
      stats.keys.sort.each do |header|
        out.puts header
        values = stats[header].keys.sort
        out.puts values.join("\t")
        out.puts values.map{|v| stats[header][v]}.join("\t")
        out.puts
      end
    end
  end
  def header(name=nil)
    @headers[name]
  end
  def puts_to(line,name)
    name = nil unless($seperate)
    files[name].puts(line) if($export && files[name])
  end
  def puts_to_all(line)
    files && files.each do |key,file|
      file.puts line
    end
  end
  def close
    files && files.each do |key,file|
      file.close
      @files[key] = nil
    end
  end
end

def if_le
  $count ||= 0
  if $print
    if $count < $print_limit
      yield
    elsif $count == $print_limit
      puts " ... "
    end
  end
  $count += 1
end

puts "Found #{$datasets.length} IMEIs"
$datasets.keys.sort.each do |imei|
  dataset = $datasets[imei]
  imsi = dataset.imsi
  events = dataset.sorted
  puts if($print)
  puts "Found #{dataset}"
  if events && ($print || $export)
    names = $event_names
    names = dataset.events_names if(names.length<1)
    export = Export.new(imei,names,dataset)
    export.export_stats(dataset.stats) if($export_stats)
    events.each do |event|
      names.each do |name|
        if event.name === name
          fields = export.header($seperate ? name : nil).map{|h| event[h]}
          export.puts_to "#{event.time_key}\t#{event.name}\t#{event.latitude}\t#{event.longitude}\t#{imsi}\t#{imei}\t#{fields.join("\t")}", name
          if_le{puts "#{event.time_key}\t#{event.name}\t#{event.latitude}\t#{event.longitude}\t#{imsi}\t#{imei}\t#{event.fields.inspect}"}
        end
      end
    end
    export.close
  end
end

